const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs-extra');
const path = require('path');
const qrcode = require('qrcode');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);
const JWT_SECRET = process.env.JWT_SECRET || 'school-event-secret-key-change-in-prod';

const dataDir = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(__dirname, 'data');
fs.ensureDirSync(dataDir);
const usersFile = path.join(dataDir, 'users.json');
const eventsFile = path.join(dataDir, 'events.json');
const attendanceFile = path.join(dataDir, 'attendance.json');
const ATTENDANCE_TIMEOUT_MIN = parseInt(process.env.ATT_TIMEOUT_MIN || '60', 10);

// Middleware
app.set('trust proxy', 1);
app.use(cors({ origin: '*' })); 
app.use(bodyParser.json());
app.use(express.static('.')); 

// Load data
const loadData = (file) => fs.readJsonSync(file, { throws: false }) || [];
const saveData = (file, data) => fs.writeJsonSync(file, data, { spaces: 2 });

// Auth middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Access token required' });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: 'Invalid token' });
    req.user = user;
    next();
  });
};

const requireAdmin = (req, res, next) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Admin only' });
  next();
};

// Routes

app.get('/api/health', (req, res) => {
  res.json({ ok: true, route: '/api/health' });
});

// Convenience health alias for quick manual checks.
app.get('/health', (req, res) => {
  res.json({ ok: true, route: '/health' });
});

// Friendly root response so service URL checks don't look broken.
app.get('/', (req, res) => {
  res.json({ ok: true, message: 'School Event API is running' });
});

// Register
app.post('/api/register', (req, res) => {
  const { username, password, role, fullName, studentId, course, section } = req.body;
  const users = loadData(usersFile);
  
  if (!username || !password) {
    return res.status(400).json({ error: 'Invalid payload' });
  }
  if (users.find(u => String(u.username).toLowerCase() === String(username).toLowerCase())) {
    return res.status(400).json({ error: 'Username already exists' });
  }
  if (!['student', 'admin', 'faculty'].includes(role)) {
    return res.status(400).json({ error: 'Invalid role' });
  }
  if (role === 'student') {
    if (!fullName || !studentId || !course || !section) {
      return res.status(400).json({ error: 'Full name, student ID, course, and section are required' });
    }
  }
  
  const newUser = {
    id: uuidv4(),
    username,
    password,
    role,
    fullName: fullName || '',
    studentId: studentId || '',
    course: course || '',
    section: section || ''
  };
  
  users.push(newUser);
  saveData(usersFile, users);
  
  const token = jwt.sign({ id: newUser.id, username: newUser.username, role: newUser.role }, JWT_SECRET, { expiresIn: '24h' });
  res.json({
    token,
    user: {
      id: newUser.id,
      username: newUser.username,
      role: newUser.role,
      fullName: newUser.fullName || '',
      studentId: newUser.studentId || '',
      course: newUser.course || '',
      section: newUser.section || ''
    },
    message: 'Account created'
  });
});

// Login
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  const users = loadData(usersFile);
  const user = users.find(u => String(u.username).toLowerCase() === String(username).toLowerCase());
  if (!user) return res.status(401).json({ error: 'Username not found' });
  if (user.password !== password) return res.status(401).json({ error: 'Wrong password' });
  
  const token = jwt.sign({ id: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: '24h' });
  res.json({
    token,
    user: {
      id: user.id,
      username: user.username,
      role: user.role,
      fullName: user.fullName || '',
      studentId: user.studentId || '',
      course: user.course || '',
      section: user.section || ''
    }
  });
});

// Events
app.get('/api/events', authenticateToken, (req, res) => {
  const events = loadData(eventsFile);
  res.json(events);
});

app.post('/api/events', authenticateToken, requireAdmin, (req, res) => {
  const events = loadData(eventsFile);
  const { name, date, status, startAt, endAt } = req.body;
  if (!name || !date) return res.status(400).json({ error: 'Invalid payload' });
  const event = {
    id: uuidv4(),
    name,
    date,
    status: ['draft', 'open', 'closed'].includes(status) ? status : 'open',
    startAt: startAt || null,
    endAt: endAt || null,
    attendees: []
  };
  events.push(event);
  saveData(eventsFile, events);
  res.json(event);
});

app.post('/api/events/:id', authenticateToken, requireAdmin, (req, res) => {
  const events = loadData(eventsFile);
  const idx = events.findIndex(e => e.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Event not found' });
  const { name, date, status, startAt, endAt } = req.body;
  if (name != null) events[idx].name = name;
  if (date != null) events[idx].date = date;
  if (status != null && ['draft', 'open', 'closed'].includes(status)) events[idx].status = status;
  events[idx].startAt = startAt || null;
  events[idx].endAt = endAt || null;
  saveData(eventsFile, events);
  res.json(events[idx]);
});

app.get('/api/faculty', authenticateToken, (req, res) => {
  const users = loadData(usersFile)
    .filter(u => u.role === 'faculty')
    .map(u => ({
      id: u.id,
      username: u.username,
      role: u.role,
      fullName: u.fullName || '',
      studentId: u.studentId || '',
      course: u.course || '',
      section: u.section || ''
    }));
  res.json(users);
});

app.delete('/api/events/:id', authenticateToken, requireAdmin, (req, res) => {
  const events = loadData(eventsFile);
  const newEvents = events.filter(e => e.id !== req.params.id);
  saveData(eventsFile, newEvents);
  res.json({ success: true });
});

// Attendees
app.post('/api/events/:eventId/attendees', authenticateToken, requireAdmin, (req, res) => {
  const { name, studentId } = req.body;
  const events = loadData(eventsFile);
  const event = events.find(e => e.id === req.params.eventId);
  if (!event) return res.status(404).json({ error: 'Event not found' });
  
  event.attendees.push({ name, studentId });
  saveData(eventsFile, events);
  res.json({ success: true });
});

// QR
app.get('/api/qr/:eventId/:studentId', (req, res) => {
  res.json({ eventId: req.params.eventId, attendeeId: req.params.studentId });
});

app.get('/api/qr/:eventId', (req, res) => {
  res.json({ eventId: req.params.eventId });
});

app.get('/api/qr-image/:eventId/:studentId', async (req, res) => {
  try {
    const payload = { eventId: req.params.eventId, attendeeId: req.params.studentId };
    const dataUrl = await qrcode.toDataURL(JSON.stringify(payload), { margin: 1, width: 200 });
    res.json({ dataUrl });
  } catch {
    res.status(500).json({ error: 'Failed to generate QR' });
  }
});

app.get('/api/qr-image/:eventId', async (req, res) => {
  try {
    const payload = { eventId: req.params.eventId };
    const dataUrl = await qrcode.toDataURL(JSON.stringify(payload), { margin: 1, width: 200 });
    res.json({ dataUrl });
  } catch {
    res.status(500).json({ error: 'Failed to generate QR' });
  }
});

// Attendance
app.post('/api/attendance', authenticateToken, (req, res) => {
  const attendance = loadData(attendanceFile);
  const { eventId, attendeeId, facultyId } = req.body;
  const events = loadData(eventsFile);
  const event = events.find(e => e.id === eventId);
  if (!event) return res.status(404).json({ error: 'Event not found' });

  if (event.status && event.status !== 'open') {
    return res.status(400).json({ error: 'Event is closed' });
  }
  const now = new Date();
  if (event.startAt) {
    const startMs = Date.parse(event.startAt);
    if (Number.isFinite(startMs) && now.getTime() < startMs) {
      return res.status(400).json({ error: 'Event not open yet' });
    }
  }
  if (event.endAt) {
    const endMs = Date.parse(event.endAt);
    if (Number.isFinite(endMs) && now.getTime() > endMs) {
      return res.status(400).json({ error: 'Event is closed' });
    }
  }

  const users = loadData(usersFile);
  const account = users.find(u => u.id === req.user.id) || {};
  const accountStudentId = account.studentId || account.username || req.user.username;
  const accountName = account.fullName || account.username || req.user.username;
  const accountCourse = account.course || '';
  const accountSection = account.section || '';

  const studentId = attendeeId || accountStudentId;
  const studentName = attendeeId ? String(attendeeId) : accountName;
  let studentCourse = accountCourse;
  let studentSection = accountSection;
  if (attendeeId) {
    const s = users.find(u => u.role === 'student' && (u.studentId === attendeeId || u.username === attendeeId));
    if (s) {
      studentCourse = s.course || '';
      studentSection = s.section || '';
    }
  }

  const facultyUserId = facultyId || (req.user.role === 'faculty' ? req.user.id : null);
  let facultyName = '';
  if (facultyUserId) {
    const f = users.find(u => u.id === facultyUserId && u.role === 'faculty');
    if (f) facultyName = f.fullName || f.username || '';
  }
  if (!facultyUserId || !facultyName) {
    return res.status(400).json({ error: 'Faculty is required' });
  }

  const todayStr = now.toDateString();
  const openIdx = attendance.findIndex(a => a.eventId === eventId && a.studentId === studentId &&
    (!a.checkOutAt) && new Date(a.checkInAt || a.timestamp).toDateString() === todayStr);
  if (openIdx !== -1) {
    const open = attendance[openIdx];
    open.checkOutAt = now.toISOString();
    open.status = 'out';
    open.checkedOutByFacultyId = facultyUserId;
    open.checkedOutByFacultyName = facultyName;
    saveData(attendanceFile, attendance);
    return res.json(open);
  }

  const rec = {
    id: uuidv4(),
    eventId,
    eventName: event.name,
    studentId,
    studentName,
    studentCourse,
    studentSection,
    status: 'in',
    timestamp: now.toISOString(),
    checkInAt: now.toISOString(),
    checkOutAt: null,
    userId: req.user.id,
    checkedInByFacultyId: facultyUserId,
    checkedInByFacultyName: facultyName,
    checkedOutByFacultyId: '',
    checkedOutByFacultyName: ''
  };
  attendance.push(rec);
  saveData(attendanceFile, attendance);
  res.json(rec);
});

app.delete('/api/attendance', authenticateToken, requireAdmin, (req, res) => {
  saveData(attendanceFile, []);
  res.json({ success: true });
});

app.delete('/api/attendance/:id', authenticateToken, requireAdmin, (req, res) => {
  const attendance = loadData(attendanceFile);
  const before = attendance.length;
  const next = attendance.filter(a => a.id !== req.params.id);
  if (next.length === before) return res.status(404).json({ error: 'Not found' });
  saveData(attendanceFile, next);
  res.json({ success: true });
});

app.get('/api/attendance', authenticateToken, (req, res) => {
  const all = loadData(attendanceFile);
  if (req.user.role === 'student') {
    return res.json(all.filter(a => a.userId === req.user.id || a.studentId === req.user.username));
  }
  if (req.user.role === 'faculty') {
    // Faculty sees only closed records that this faculty handled at checkout/timeout.
    return res.json(
      all.filter(a => a.checkOutAt && a.checkedOutByFacultyId === req.user.id),
    );
  }
  res.json(all);
});

app.get('/api/attendance/me', authenticateToken, (req, res) => {
  const all = loadData(attendanceFile);
  res.json(all.filter(a => a.userId === req.user.id || a.studentId === req.user.username));
});

app.delete('/api/attendance/me', authenticateToken, (req, res) => {
  const all = loadData(attendanceFile);
  const next = all.filter(a => !(a.userId === req.user.id || a.studentId === req.user.username));
  saveData(attendanceFile, next);
  res.json({ success: true });
});

// Auto-timeout closer
setInterval(() => {
  try {
    const attendance = loadData(attendanceFile);
    const now = Date.now();
    let changed = false;
    for (const a of attendance) {
      if (!a.checkOutAt && a.checkInAt) {
        const start = Date.parse(a.checkInAt);
        if (Number.isFinite(start) && now - start > ATTENDANCE_TIMEOUT_MIN * 60 * 1000) {
          a.checkOutAt = new Date(start + ATTENDANCE_TIMEOUT_MIN * 60 * 1000).toISOString();
          a.status = 'timeout';
          // Assign timeout ownership so faculty filtering stays strict and deterministic.
          if (!a.checkedOutByFacultyId) {
            a.checkedOutByFacultyId = a.checkedInByFacultyId || '';
            a.checkedOutByFacultyName = a.checkedInByFacultyName || '';
          }
          changed = true;
        }
      }
    }
    if (changed) saveData(attendanceFile, attendance);
  } catch {}
}, 60 * 1000);

app.get('/api/reports/attendance', authenticateToken, requireAdmin, (req, res) => {
  const all = loadData(attendanceFile);
  const toCsv = rows => {
    const header = ['eventName','studentName','studentId','status','timestamp','userId'];
    const lines = [header.join(',')];
    for (const r of rows) {
      const cells = [r.eventName, r.studentName, r.studentId, r.status, r.timestamp, r.userId].map(v => `"${String(v).replace(/"/g,'""')}"`);
      lines.push(cells.join(','));
    }
    return lines.join('\n');
  };
  if ((req.query.format || '').toLowerCase() === 'csv') {
    const csv = toCsv(all);
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="attendance.csv"');
    return res.send(csv);
  }
  const byEvent = {};
  for (const r of all) {
    byEvent[r.eventId] = byEvent[r.eventId] || { eventId: r.eventId, eventName: r.eventName, total: 0 };
    byEvent[r.eventId].total += 1;
  }
  res.json(Object.values(byEvent));
});

app.get('/api/users', authenticateToken, requireAdmin, (req, res) => {
  const users = loadData(usersFile).map(u => ({
    id: u.id,
    username: u.username,
    role: u.role,
    fullName: u.fullName || '',
    studentId: u.studentId || '',
    course: u.course || '',
    section: u.section || ''
  }));
  res.json(users);
});

app.post('/api/users', authenticateToken, requireAdmin, (req, res) => {
  const { username, password, role, fullName, studentId, course, section } = req.body;
  const users = loadData(usersFile);
  if (!username || !password || !['student','admin','faculty'].includes(role)) {
    return res.status(400).json({ error: 'Invalid payload' });
  }
  if (role === 'student') {
    if (!fullName || !studentId || !course || !section) {
      return res.status(400).json({ error: 'Full name, student ID, course, and section are required' });
    }
  }
  if (users.find(u => u.username.toLowerCase() === username.toLowerCase())) {
    return res.status(400).json({ error: 'Username exists' });
  }
  const u = { id: uuidv4(), username, password, role, fullName: fullName || '', studentId: studentId || '', course: course || '', section: section || '' };
  users.push(u);
  saveData(usersFile, users);
  res.json({ id: u.id, username: u.username, role: u.role, fullName: u.fullName || '', studentId: u.studentId || '', course: u.course || '', section: u.section || '' });
});

app.patch('/api/users/:id', authenticateToken, requireAdmin, (req, res) => {
  const users = loadData(usersFile);
  const idx = users.findIndex(u => u.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  const { password, role } = req.body;
  if (password) users[idx].password = password;
  if (role && ['student','admin','faculty'].includes(role)) users[idx].role = role;
  saveData(usersFile, users);
  const u = users[idx];
  res.json({ id: u.id, username: u.username, role: u.role });
});

app.delete('/api/users/:id', authenticateToken, requireAdmin, (req, res) => {
  let users = loadData(usersFile);
  const before = users.length;
  users = users.filter(u => u.id !== req.params.id);
  if (users.length === before) return res.status(404).json({ error: 'Not found' });
  saveData(usersFile, users);
  res.json({ success: true });
});
app.get('/api/attendance/stats', authenticateToken, (req, res) => {
  const attendance = loadData(attendanceFile);
  const today = new Date().toDateString();
  const presentToday = attendance.filter(a => new Date(a.timestamp).toDateString() === today).length;
  res.json({
    total: attendance.length,
    today: presentToday
  });
});

// Serve frontend
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
