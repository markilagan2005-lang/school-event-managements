 const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs-extra');
const path = require('path');
const qrcode = require('qrcode');
const { MongoClient } = require('mongodb');
const bcrypt = require('bcryptjs'); // Import bcryptjs
const nodemailer = require('nodemailer');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);
const JWT_SECRET = process.env.JWT_SECRET || 'school-event-secret-key-change-in-prod';
const BCRYPT_SALT_ROUNDS = 10; // For password hashing
const fileToCollection = new Map();

const dataDir = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(__dirname, 'data');
fs.ensureDirSync(dataDir);
const usersFile = path.join(dataDir, 'users.json');
const eventsFile = path.join(dataDir, 'events.json');
const attendanceFile = path.join(dataDir, 'attendance.json');
const registrationOtpsFile = path.join(dataDir, 'registrationOtps.json');
fileToCollection.set(usersFile, 'users');
fileToCollection.set(eventsFile, 'events');
fileToCollection.set(attendanceFile, 'attendance');
fileToCollection.set(registrationOtpsFile, 'registrationOtps');
const ATTENDANCE_TIMEOUT_MIN = parseInt(process.env.ATT_TIMEOUT_MIN || '60', 10);
const DEFAULT_ADMIN_USERNAME = process.env.DEFAULT_ADMIN_USERNAME || 'admin';
const DEFAULT_ADMIN_PASSWORD = process.env.DEFAULT_ADMIN_PASSWORD || '@LCCADMIN2026';
const DEFAULT_ADMIN_FULLNAME = process.env.DEFAULT_ADMIN_FULLNAME || 'System Admin';
const MONGODB_URI = (process.env.MONGODB_URI_DIRECT || process.env.MONGODB_URI || '').trim();
const MONGODB_DB_NAME = (process.env.MONGODB_DB_NAME || 'attendify').trim();
const GMAIL_USER = (process.env.GMAIL_USER || '').trim();
const GMAIL_APP_PASSWORD = (process.env.GMAIL_APP_PASSWORD || '').trim();
const BREVO_API_KEY = (process.env.BREVO_API_KEY || '').trim();
const BREVO_SENDER_NAME = (process.env.BREVO_SENDER_NAME || formatAppName()).trim();
const BREVO_SENDER_EMAIL = (process.env.BREVO_SENDER_EMAIL || GMAIL_USER || '').trim();
const OTP_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
const OTP_RESEND_COOLDOWN_MS = 60 * 1000; // 1 minute between resends

// ----- Nodemailer (Gmail) transport -----
// NOTE: SMTP (both ports 465 and 587) is completely blocked on Render Free Tier egress.
// Gmail SMTP transporter is initialized here for non-Render environments only.
let mailTransporter = null;
try {
  if (GMAIL_USER && GMAIL_APP_PASSWORD) {
    mailTransporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 587,
      secure: false,
      requireTLS: true,
      auth: {
        user: GMAIL_USER,
        pass: GMAIL_APP_PASSWORD,
      },
      connectionTimeout: 12000,
      greetingTimeout: 10000,
      socketTimeout: 15000,
      pool: false,
      maxConnections: 1,
      maxMessages: 10,
      tls: {
        rejectUnauthorized: true,
        servername: 'smtp.gmail.com',
        minVersion: 'TLSv1.2',
      },
    });
  }
} catch (err) {
  console.warn('[mail] Failed to initialize Gmail transport:', err?.message || err);
  mailTransporter = null;
}

const SMTP_SEND_TIMEOUT_MS = 15000;
const HTTP_SEND_TIMEOUT_MS = 15000;
const BREVO_API_BASE = 'https://api.brevo.com/v3';

// HTTPS API fallback for Brevo (https://www.brevo.com/) — works over port 443,
// which is never blocked by Render Free Tier egress.
// Free Tier: 300 emails / day. No credit card required.
const sendViaBrevoApi = async ({ toEmail, otp, username }) => {
  if (!BREVO_API_KEY) return { ok: false, reason: 'brevo-api-key-missing' };
  const senderEmail = BREVO_SENDER_EMAIL || GMAIL_USER;
  if (!senderEmail) return { ok: false, reason: 'no-sender-email' };

  const subject = `Your ${formatAppName()} verification code is ${otp}`;
  const text = [
    `Hi ${username || 'there'},`,
    '',
    `Welcome to ${formatAppName()}!`,
    '',
    `Your 6-digit verification code is: ${otp}`,
    `This code will expire in 10 minutes.`,
    '',
    `If you did not create an account, you can safely ignore this email.`,
    '',
    `— The ${formatAppName()} Team`,
  ].join('\n');
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #111;">
      <h2 style="margin: 0 0 16px; color: #4F46E5;">${formatAppName()}</h2>
      <p style="font-size: 15px;">Hi ${username || 'there'},</p>
      <p style="font-size: 15px;">Welcome! Use the verification code below to activate your account:</p>
      <div style="text-align:center; margin: 24px 0;">
        <div style="display:inline-block; font-size: 32px; letter-spacing: 12px; padding: 14px 28px; border-radius: 10px; background: #EEF2FF; color: #4338CA; font-weight: 700;">${otp}</div>
      </div>
      <p style="font-size: 14px; color: #555;">This code will expire in 10 minutes.</p>
      <p style="font-size: 14px; color: #888;">If you did not create an account, you can safely ignore this email.</p>
    </div>`;

  const payload = {
    sender: { name: BREVO_SENDER_NAME || formatAppName(), email: senderEmail },
    to: [{ email: toEmail, name: username || toEmail }],
    subject,
    textContent: text,
    htmlContent: html,
  };

  let cancel;
  const timeoutPromise = new Promise((resolve) => {
    cancel = setTimeout(() => resolve({ __timedOut: true }), HTTP_SEND_TIMEOUT_MS);
  });

  let respJson;
  try {
    const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const fetchPromise = globalThis.fetch(`${BREVO_API_BASE}/smtp/email`, {
      method: 'POST',
      headers: {
        'api-key': BREVO_API_KEY,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify(payload),
      signal: controller?.signal,
    }).then(async (r) => {
      const body = await r.text();
      let parsed;
      try { parsed = JSON.parse(body); } catch { parsed = { raw: body }; }
      return { status: r.status, ok: r.ok, body: parsed, raw: body };
    });
    const raced = await Promise.race([fetchPromise, timeoutPromise]);
    if (cancel) clearTimeout(cancel);
    if (raced && raced.__timedOut) {
      if (controller) controller.abort();
      return { ok: false, reason: 'brevo-http-timeout', error: `Brevo API timed out after ${HTTP_SEND_TIMEOUT_MS}ms` };
    }
    respJson = raced;
    if (!respJson.ok) {
      console.error('[mail][brevo] Non-2xx:', respJson.status, respJson.raw || respJson.body);
      return {
        ok: false,
        reason: `brevo-http-${respJson.status}`,
        error: `Brevo API HTTP ${respJson.status}: ${JSON.stringify(respJson.body || respJson.raw)}`,
      };
    }
    console.log(`[mail][brevo] Send OK: messageId=${respJson.body?.messageId || JSON.stringify(respJson.body)}`);
    return { ok: true, info: respJson.body };
  } catch (err) {
    if (cancel) clearTimeout(cancel);
    console.error('[mail][brevo] Fetch error:', err?.message || err);
    return { ok: false, reason: 'brevo-http-exception', error: String(err?.message || err) };
  }
};

const formatAppName = () => 'School Event Manager';

const sendEmailCode = async ({ toEmail, otp, username }) => {
  if (!toEmail) return { ok: false, reason: 'no-recipient' };

  // Always log the OTP so testing works even without any email transport configured.
  console.log(`[mail][code] Email=${toEmail} Username=${username} OTP=${otp}`);

  // Strategy: Brevo HTTPS API (port 443 — guaranteed on Render Free) FIRST,
  // then Gmail SMTP fallback (works on non-Render hosts where egress isn't firewalled).
  const subject = `Your ${formatAppName()} verification code is ${otp}`;

  // 1. Try Brevo (pure HTTPS 443) first
  if (BREVO_API_KEY) {
    try {
      const brevoResult = await sendViaBrevoApi({ toEmail, otp, username });
      if (brevoResult.ok) return brevoResult;
      console.warn('[mail] Brevo transport failed, falling back to Gmail SMTP if available:', brevoResult.error || brevoResult.reason);
    } catch (err) {
      console.warn('[mail] Brevo transport exception, falling back to Gmail SMTP if available:', err?.message || err);
    }
  }

  // 2. Fallback: Gmail SMTP (ports 465/587) — blocked on Render Free but works elsewhere.
  if (!mailTransporter) {
    return { ok: false, reason: 'gmail-not-configured', otp };
  }

  let sendPromise;
  try {
    const text = [
      `Hi ${username || 'there'},`,
      '',
      `Welcome to ${formatAppName()}!`,
      '',
      `Your 6-digit verification code is: ${otp}`,
      `This code will expire in 10 minutes.`,
      '',
      `If you did not create an account, you can safely ignore this email.`,
      '',
      `— The ${formatAppName()} Team`,
    ].join('\n');
    const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #111;">
      <h2 style="margin: 0 0 16px; color: #4F46E5;">${formatAppName()}</h2>
      <p style="font-size: 15px;">Hi ${username || 'there'},</p>
      <p style="font-size: 15px;">Welcome! Use the verification code below to activate your account:</p>
      <div style="text-align:center; margin: 24px 0;">
        <div style="display:inline-block; font-size: 32px; letter-spacing: 12px; padding: 14px 28px; border-radius: 10px; background: #EEF2FF; color: #4338CA; font-weight: 700;">${otp}</div>
      </div>
      <p style="font-size: 14px; color: #555;">This code will expire in 10 minutes.</p>
      <p style="font-size: 14px; color: #888;">If you did not create an account, you can safely ignore this email.</p>
    </div>`;

    sendPromise = mailTransporter.sendMail({
      from: `${formatAppName()} <${GMAIL_USER}>`,
      to: toEmail,
      subject,
      text,
      html,
    });
  } catch (err) {
    console.error('[mail] sendMail start sync error:', err?.message || err);
    return { ok: false, reason: 'send-start-failed', error: String(err?.message || err), otp };
  }

  let timeoutRef = null;
  const timeoutPromise = new Promise((resolve) => {
    timeoutRef = setTimeout(() => {
      resolve({ __timedOut: true });
    }, SMTP_SEND_TIMEOUT_MS);
  });

  try {
    const result = await Promise.race([sendPromise, timeoutPromise]);
    if (timeoutRef) clearTimeout(timeoutRef);
    if (result && result.__timedOut) {
      const msg = `smtp-timeout-after-${SMTP_SEND_TIMEOUT_MS}ms (Render egress may block Gmail SMTP — set BREVO_API_KEY env to use HTTPS 443 Brevo API)`;
      console.error(`[mail] Send timed out: ${msg}`);
      return { ok: false, reason: 'send-timeout', error: msg, otp };
    }
    console.log(`[mail] Send OK: accepted=${JSON.stringify(result?.accepted || [])} messageId=${result?.messageId || ''}`);
    return { ok: true, info: { messageId: result?.messageId, accepted: result?.accepted || [] } };
  } catch (err) {
    if (timeoutRef) clearTimeout(timeoutRef);
    console.error('[mail] Send failed:', err?.message || err);
    return { ok: false, reason: 'send-failed', error: String(err?.message || err), otp };
  }
};

const generateOtp = () => {
  // 6-digit code, no leading zeros.
  const n = Math.floor(100000 + Math.random() * 900000);
  return String(n);
};

const setUserOtp = (user, otp, now = Date.now()) => {
  user.verificationOtp = String(otp);
  user.verificationOtpExpiry = now + OTP_EXPIRY_MS;
  user.verificationOtpLastSent = now;
  // Legacy fields, kept for compat:
  user.verificationToken = uuidv4();
  user.verificationTokenExpiry = now + OTP_EXPIRY_MS;
};

const isValidOtpForUser = (user, candidate, now = Date.now()) => {
  if (!user) return { ok: false, code: 'NO_USER' };
  if (user.isVerified === true) return { ok: false, code: 'ALREADY_VERIFIED' };
  const stored = String(user.verificationOtp || '');
  if (!stored) return { ok: false, code: 'NO_CODE' };
  const exp = parseInt(user.verificationOtpExpiry || '0', 10);
  if (!exp || now > exp) return { ok: false, code: 'EXPIRED' };
  if (String(candidate || '').trim() !== stored) return { ok: false, code: 'WRONG_CODE' };
  return { ok: true };
};

// Middleware
app.set('trust proxy', 1);
app.use(cors({ origin: '*' }));
const MAX_BODY_MB = 5;
const MAX_BODY_BYTES = MAX_BODY_MB * 1024 * 1024;
app.use(bodyParser.json({ limit: MAX_BODY_BYTES }));
app.use(bodyParser.urlencoded({ extended: true, limit: MAX_BODY_BYTES }));
// Catch body-parser 413 / payload errors and return JSON (never Render's default HTML "Payload Too Large" page).
app.use((err, req, res, next) => {
  if (err && err.type === 'entity.too.large') {
    return res.status(413).json({
      error: 'Payload too large',
      message: `Request body exceeds the ${MAX_BODY_MB}MB limit. Compress your poster image and try again.`,
      maxSizeMb: MAX_BODY_MB,
    });
  }
  if (err && err.status && err.status >= 400) {
    return res.status(err.status).json({
      error: err.message || 'Bad request',
    });
  }
  next(err);
});
app.use(express.static('.')); 

// Storage (JSON files + optional MongoDB mirror)
let mongoClient = null;
let mongoDb = null;
const writeChains = new Map();

const cleanMongoDoc = (doc) => {
  if (!doc || typeof doc !== 'object') return doc;
  const { _id, ...rest } = doc;
  return rest;
};

const loadData = (file) => fs.readJsonSync(file, { throws: false }) || [];

const enqueueMongoWrite = (collectionName, data) => {
  if (!mongoDb || !collectionName) return;
  const prev = writeChains.get(collectionName) || Promise.resolve();
  const next = prev
    .catch(() => {})
    .then(async () => {
      const col = mongoDb.collection(collectionName);
      await col.deleteMany({});
      if (Array.isArray(data) && data.length > 0) {
        await col.insertMany(data);
      }
    })
    .catch((err) => {
      console.error(`[mongo] Failed to sync ${collectionName}:`, err?.message || err);
    });
  writeChains.set(collectionName, next);
};

const saveData = (file, data) => {
  fs.writeJsonSync(file, data, { spaces: 2 });
  const collectionName = fileToCollection.get(file);
  enqueueMongoWrite(collectionName, data);
};

const syncCollectionFromMongoIfAny = async (file, collectionName) => {
  if (!mongoDb) return;
  const col = mongoDb.collection(collectionName);
  const docs = (await col.find({}).toArray()).map(cleanMongoDoc);
  if (docs.length > 0) {
    fs.writeJsonSync(file, docs, { spaces: 2 });
    return;
  }
  const local = loadData(file);
  if (local.length > 0) {
    await col.insertMany(local);
  }
};

const initializeMongoMirror = async () => {
  if (!MONGODB_URI) {
    console.warn(
      '[mongo] ⚠️  MONGODB_URI not set — data is stored ONLY in local JSON files.\n' +
      '       On Render free tier this means ALL accounts/events/attendance are LOST\n' +
      '       on every redeploy or container restart. Fix this:\n' +
      '         1. Go to Render dashboard → your service → Environment\n' +
      '         2. Add env var MONGODB_URI with your MongoDB Atlas connection string\n' +
      '            (e.g. mongodb+srv://<user>:<pw>@cluster0.xyz.mongodb.net/?retryWrites=true&w=majority)\n' +
      '         3. Save Changes → wait for auto-redeploy.',
    );
    return;
  }
  try {
    mongoClient = new MongoClient(MONGODB_URI, {
      connectTimeoutMS: 15000,
      serverSelectionTimeoutMS: 15000,
    });
    await mongoClient.connect();
    mongoDb = mongoClient.db(MONGODB_DB_NAME);
    console.log(`[mongo] ✅ Connected to MongoDB database "${MONGODB_DB_NAME}".`);
    console.log('[mongo] Persistent collections: users, events, attendance, registrationOtps');
    const collections = [
      [usersFile, 'users'],
      [eventsFile, 'events'],
      [attendanceFile, 'attendance'],
      [registrationOtpsFile, 'registrationOtps'],
    ];
    for (const [file, name] of collections) {
      try {
        await syncCollectionFromMongoIfAny(file, name);
      } catch (collErr) {
        console.error(`[mongo] Failed to sync collection "${name}":`, collErr?.message || collErr);
      }
    }
    console.log('[mongo] ✅ All collections synced.');
  } catch (err) {
    const msg = err?.message || String(err);
    console.error('[mongo] ❌ MongoDB connection FAILED — falling back to JSON file storage.');
    if (msg.toLowerCase().includes('authentication') || msg.toLowerCase().includes('credential')) {
      console.error('[mongo]    → Root cause: Authentication failed. Double-check your MONGODB_URI password or database user.');
    } else if (msg.toLowerCase().includes('ip') || msg.toLowerCase().includes('whitelist') || msg.toLowerCase().includes('allowlist')) {
      console.error('[mongo]    → Root cause: MongoDB Atlas IP not whitelisted. In Atlas, go to Network Access → Add IP Address → Allow Access from Anywhere (0.0.0.0/0) for Render.');
    } else if (msg.toLowerCase().includes('timeout') || msg.toLowerCase().includes('server selection')) {
      console.error('[mongo]    → Root cause: Connection timed out. Check MONGODB_URI spelling, cluster name, and whether Atlas cluster is currently paused.');
    } else if (msg.toLowerCase().includes('dns') || msg.toLowerCase().includes('getaddrinfo')) {
      console.error('[mongo]    → Root cause: DNS/network failure. Double-check your MONGODB_URI hostname.');
    }
    console.error(`[mongo]    Raw error: ${msg}`);
    mongoClient = null;
    mongoDb = null;
  }
};
const normalizeStudentId = (value) => String(value || '').trim().toLowerCase();
const hasDuplicateStudentId = (users, studentId, exceptUserId = null) => {
  const normalized = normalizeStudentId(studentId);
  if (!normalized) return false;
  return users.some(
    (u) => u.id !== exceptUserId && normalizeStudentId(u.studentId) === normalized,
  );
};
const hasDuplicateUserId = (users, userId, exceptUserId = null) => {
  const normalized = String(userId || '').trim();
  if (!normalized) return false;
  return users.some((u) => u.id !== exceptUserId && String(u.id) === normalized);
};
const isFacultyApproved = (user) => {
  if (!user || user.role !== 'faculty') return true;
  return user.isApproved === true;
};

// Password Hashing and Validation
const hashPassword = async (password) => {
  return await bcrypt.hash(password, BCRYPT_SALT_ROUNDS);
};

const comparePassword = async (password, hash) => {
  return await bcrypt.compare(password, hash);
};

const isStrongPassword = (password) => {
  // At least 8 characters long
  // Contains at least one uppercase letter
  // Contains at least one lowercase letter
  // Contains at least one digit
  // Contains at least one special character
  const strongPasswordRegex = new RegExp('^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$%^&*])(?=.{8,})');
  return strongPasswordRegex.test(password);
};

const toPublicUser = (u) => ({
  id: u.id,
  username: u.username,
  role: u.role,
  fullName: u.fullName || '',
  studentId: u.studentId || '',
  course: u.course || '',
  section: u.section || '',
  isApproved: isFacultyApproved(u),
  isVerified: u.isVerified || false,
});

const ensureDefaultAdmin = async () => {
  const users = loadData(usersFile);
  const username = String(DEFAULT_ADMIN_USERNAME).trim();
  if (!username) return;

  let changed = false;
  const existing = users.find(u => String(u.username).toLowerCase() === username.toLowerCase());
  if (!existing) {
    const hashedPassword = await hashPassword(DEFAULT_ADMIN_PASSWORD);
    users.push({
      id: uuidv4(),
      username,
      password: hashedPassword,
      role: 'admin',
      fullName: DEFAULT_ADMIN_FULLNAME,
      studentId: '',
      course: '',
      section: '',
      isApproved: true,
      isVerified: true,
    });
    changed = true;
  } else {
    if (existing.role !== 'admin') {
      existing.role = 'admin';
      changed = true;
    }
    // If password is stored as plaintext (unhashed), re-hash it.
    if (String(existing.password).length < 20 || !String(existing.password).startsWith('$2')) {
      const hashedPassword = await hashPassword(
        String(existing.password).trim().isNotEmpty ? String(existing.password).trim() : DEFAULT_ADMIN_PASSWORD
      );
      existing.password = hashedPassword;
      changed = true;
    }
    if (!existing.fullName) {
      existing.fullName = DEFAULT_ADMIN_FULLNAME;
      changed = true;
    }
    if (existing.isApproved !== true) {
      existing.isApproved = true;
      changed = true;
    }
    if (existing.isVerified !== true) {
      existing.isVerified = true;
      changed = true;
    }
  }

  if (changed) saveData(usersFile, users);
};

// Auth middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Access token required' });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: 'Invalid token' });
    const users = loadData(usersFile);
    const account = users.find((u) => u.id === user.id);
    if (!account) return res.status(401).json({ error: 'Account not found' });
    if (!isFacultyApproved(account)) {
      return res.status(403).json({ error: 'Faculty account is pending admin approval' });
    }
    req.user = {
      id: account.id,
      username: account.username,
      role: account.role,
    };
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
app.post('/api/register', async (req, res) => {
  const { username, password, role, fullName, studentId, course, section, email,
          registrationOtp, registrationOtpRef } = req.body;
  const users = loadData(usersFile);

  if (!['student', 'faculty'].includes(role)) {
    return res.status(400).json({ error: 'Public registration is only for student/faculty' });
  }

  const identifier = role === 'student' ? email : username;
  if (!identifier || !password) {
    return res.status(400).json({ error: role === 'student' ? 'Email and password are required' : 'Username and password are required' });
  }
  if (!isStrongPassword(password)) {
    return res.status(400).json({
      error: 'Password must be at least 8 characters long, contain at least one uppercase letter, one lowercase letter, one digit, and one special character (!@#$%^&*)',
    });
  }

  // -------- STUDENT: PRE-REGISTRATION OTP CHECK FIRST --------
  let verifiedStudentEmail = null;
  if (role === 'student') {
    const normalizedEmail = String(email || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
      return res.status(400).json({ error: 'Enter a valid Gmail / email address.' });
    }
    if (!registrationOtp || !String(registrationOtp).trim()) {
      return res.status(400).json({ error: 'Enter the 6-digit code sent to your email first. If you did not get one, tap "Send verification code".' });
    }
    // Duplicate email check BEFORE consuming OTP
    if (findUserByHandle(users, normalizedEmail)) {
      return res.status(409).json({ error: 'This email is already registered. Try logging in or use "Reset Password".' });
    }
    if (!fullName || !studentId || !course || !section) {
      return res.status(400).json({ error: 'Full name, student ID, course, and section are required' });
    }
    // VALIDATE pre-registration OTP (consume it — one-time use)
    const check = await consumeRegistrationOtp(
      normalizedEmail,
      registrationOtp,
      registrationOtpRef || '',
    );
    if (!check.ok) {
      switch (check.error) {
        case 'EXPIRED':
          return res.status(410).json({ error: check.message });
        case 'WRONG_CODE':
        case 'TOO_MANY_ATTEMPTS':
          return res.status(401).json({ error: check.message });
        case 'NO_PENDING':
          return res.status(400).json({ error: check.message });
        case 'BAD_INPUT':
        default:
          return res.status(400).json({ error: check.message });
      }
    }
    verifiedStudentEmail = normalizedEmail;
  }

  // -------- Duplicate / ID checks AFTER email verified for student --------
  if (users.find(u => String(u.username).toLowerCase() === String(role === 'student'
    ? verifiedStudentEmail.toLowerCase()
    : username).toLowerCase())) {
    return res.status(400).json({ error: role === 'student' ? 'This email is already registered.' : 'Username already exists' });
  }
  if (hasDuplicateStudentId(users, studentId)) {
    return res.status(400).json({ error: 'This ID is already have' });
  }

  const hashedPassword = await hashPassword(password);
  const normalizedEmail = role === 'student'
    ? verifiedStudentEmail
    : (email || username || '').toString().trim();
  // For STUDENTS: use the email as the canonical username so they can log in
  // with just their email address. Also lower-case it for stable lookup.
  const canonicalUsername = role === 'student'
    ? verifiedStudentEmail
    : username;

  const newUser = {
    id: uuidv4(),
    username: canonicalUsername,
    email: normalizedEmail || username,
    password: hashedPassword,
    role,
    fullName: fullName || '',
    studentId: studentId || '',
    course: course || '',
    section: section || '',
    isApproved: role === 'faculty' ? false : true,
    // STUDENT email was ALREADY PROVEN via pre-registration OTP before we got here.
    // So set isVerified=true IMMEDIATELY — no second verification gate on login.
    isVerified: true,
  };

  if (role === 'faculty') {
    // Faculty: no OTP flow; legacy token-based admin approval.
    newUser.verificationToken = uuidv4();
    newUser.verificationTokenExpiry = Date.now() + 3600 * 1000;
    newUser.isVerified = false; // faculty require admin approval to verify
  }

  users.push(newUser);
  saveData(usersFile, users);

  if (newUser.role === 'faculty') {
    return res.json({
      user: toPublicUser(newUser),
      message: 'Faculty registration submitted. Wait for admin verification before login.',
    });
  }

  // -------- STUDENT SUCCESS: email already verified above. Issue JWT directly --------
  const token = jwt.sign(
    { id: newUser.id, username: newUser.username, role: newUser.role },
    JWT_SECRET,
    { expiresIn: '24h' },
  );
  return res.status(201).json({
    ok: true,
    message: 'Account created and email verified. You are now logged in.',
    token,
    user: toPublicUser(newUser),
  });
});

// Verify Email (legacy token-based link; kept for direct email links and admin bypass scenarios)
app.get('/api/verify-email', (req, res) => {
  const { token } = req.query;
  const users = loadData(usersFile);

  const user = users.find(u => u.verificationToken === token);
  if (!user) {
    return res.status(400).json({ error: 'Invalid verification token' });
  }
  if (user.isVerified) {
    return res.status(200).json({ message: 'Email already verified' });
  }
  if (user.verificationTokenExpiry < Date.now()) {
    return res.status(400).json({ error: 'Verification token expired' });
  }

  user.isVerified = true;
  user.verificationToken = undefined; // Clear token after use
  user.verificationTokenExpiry = undefined; // Clear expiry after use
  if (user.verificationOtp !== undefined) user.verificationOtp = undefined;
  if (user.verificationOtpExpiry !== undefined) user.verificationOtpExpiry = undefined;
  if (user.verificationOtpLastSent !== undefined) user.verificationOtpLastSent = undefined;
  saveData(usersFile, users);

  return res.status(200).json({ message: 'Email verified successfully. You can now log in.' });
});

// --- New OTP-based verification endpoints (used by the app) ---
// Look up a user by username OR email (case insensitive)
const findUserByHandle = (users, handle, mode) => {
  if (!handle) return null;
  const h = String(handle).trim().toLowerCase();
  if (!h) return null;
  const m = typeof mode === 'string' ? mode.trim().toLowerCase() : 'auto';
  const findByUsername = () => users.find(u => String(u.username || '').toLowerCase() === h) || null;
  const findByEmail = () => users.find(u => u && u.email && String(u.email).toLowerCase() === h) || null;
  const findByStudentId = () => users.find(u => u && u.studentId && String(u.studentId).toLowerCase() === h) || null;
  if (m === 'username') return findByUsername();
  if (m === 'email') return findByEmail();
  if (m === 'studentid') return findByStudentId();
  // auto (backward compat): check all three OR'd
  return findByUsername() || findByEmail() || findByStudentId() || null;
};

// --- Pre-registration email OTP (students MUST prove email ownership BEFORE account creation) ---

// Store a new pending registration OTP for a given email.
// Returns { ref, otpPlain, expiresAtMs, lastSentAt, cooldownRemainingMs? }
const storeRegistrationOtp = async (emailRaw) => {
  const email = String(emailRaw || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { ok: false, error: 'INVALID_EMAIL', message: 'Enter a valid Gmail / email address.' };
  }
  const now = Date.now();
  const pending = loadData(registrationOtpsFile);
  // Clean up expired entries first (storage sweep)
  const live = pending.filter(r => !r.expiresAtMs || r.expiresAtMs > now - 24 * 60 * 60 * 1000);
  const existingIdx = live.findIndex(r => String(r.email).toLowerCase() === email);
  const existing = existingIdx >= 0 ? live[existingIdx] : null;
  // Enforce resend cooldown
  if (existing && existing.lastSentAt && (now - existing.lastSentAt) < OTP_RESEND_COOLDOWN_MS) {
    const waitMs = OTP_RESEND_COOLDOWN_MS - (now - existing.lastSentAt);
    return {
      ok: false,
      error: 'COOLDOWN',
      retryAfterSec: Math.max(1, Math.ceil(waitMs / 1000)),
      message: `Wait ${Math.max(1, Math.ceil(waitMs / 1000))}s before requesting another code.`,
    };
  }
  const otpPlain = generateOtp();
  const otpHash = await bcrypt.hash(otpPlain, BCRYPT_SALT_ROUNDS);
  const ref = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  const expiresAtMs = now + OTP_EXPIRY_MS;
  const record = {
    ref,
    email,
    otpHash,
    expiresAtMs,
    lastSentAt: now,
    createdAt: existing?.createdAt || now,
    attempts: 0,
  };
  if (existingIdx >= 0) {
    record.createdAt = live[existingIdx].createdAt;
    live[existingIdx] = record;
  } else {
    live.push(record);
  }
  saveData(registrationOtpsFile, live);
  return { ok: true, ref, otpPlain, expiresAtMs, lastSentAt: now, expiresInMs: OTP_EXPIRY_MS };
};

const consumeRegistrationOtp = async (emailRaw, otpCandidate, refRaw) => {
  const email = String(emailRaw || '').trim().toLowerCase();
  const candidate = String(otpCandidate || '').trim();
  const ref = String(refRaw || '').trim();
  if (!email || !candidate || !/^\d{6}$/.test(candidate)) {
    return { ok: false, error: 'BAD_INPUT', message: 'Enter the 6-digit code sent to your email.' };
  }
  const now = Date.now();
  const pending = loadData(registrationOtpsFile);
  const idx = pending.findIndex(r => String(r.email).toLowerCase() === email && (!ref || r.ref === ref));
  if (idx < 0) {
    return { ok: false, error: 'NO_PENDING', message: 'No code pending for this email. Tap "Send verification code" first.' };
  }
  const rec = pending[idx];
  rec.attempts = Number(rec.attempts || 0) + 1;
  if (rec.expiresAtMs && rec.expiresAtMs < now) {
    pending.splice(idx, 1);
    saveData(registrationOtpsFile, pending);
    return { ok: false, error: 'EXPIRED', message: 'This code has expired. Tap "Send verification code" to get a new one.' };
  }
  const match = await bcrypt.compare(candidate, rec.otpHash);
  if (!match) {
    if (rec.attempts >= 10) {
      pending.splice(idx, 1);
      saveData(registrationOtpsFile, pending);
      return { ok: false, error: 'TOO_MANY_ATTEMPTS', message: 'Too many wrong attempts. Send a new code and try again.' };
    }
    saveData(registrationOtpsFile, pending);
    return { ok: false, error: 'WRONG_CODE', message: 'Incorrect 6-digit code. Double-check your email (and Spam folder).' };
  }
  // Success: consume / delete the pending record so it can't be reused
  pending.splice(idx, 1);
  saveData(registrationOtpsFile, pending);
  return { ok: true, email, message: 'Email ownership verified.' };
};

// Step 1 of student registration: send a 6-digit OTP to the email the student typed.
// NO account is created here. This only proves the student controls the Gmail inbox.
app.post('/api/send-registration-otp', async (req, res) => {
  const { email } = req.body;
  const normalizedEmail = String(email || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
    return res.status(400).json({ error: 'Enter a valid Gmail / email address.' });
  }
  // Duplicate check: if email already belongs to a registered user, refuse to send.
  const users = loadData(usersFile);
  if (findUserByHandle(users, normalizedEmail)) {
    return res.status(409).json({ error: 'This email is already registered. Try logging in or use "Reset Password".' });
  }
  const stored = await storeRegistrationOtp(normalizedEmail);
  if (!stored.ok) {
    if (stored.error === 'COOLDOWN') {
      return res.status(429).json({
        error: stored.message,
        retryAfterSec: stored.retryAfterSec,
      });
    }
    return res.status(400).json({ error: stored.message });
  }
  // Email delivery (best-effort; server console always prints the OTP as fallback)
  let mailResult = { ok: false, reason: 'skipped' };
  try {
    mailResult = await sendEmailCode({
      toEmail: normalizedEmail,
      otp: stored.otpPlain,
      username: normalizedEmail,
    });
  } catch (err) {
    console.error('[send-registration-otp][mail] Error:', err);
    mailResult = { ok: false, reason: 'exception', error: String(err?.message || err) };
  }
  return res.status(200).json({
    ok: true,
    ref: stored.ref,
    expiresInMs: stored.expiresInMs,
    email: normalizedEmail,
    emailSent: mailResult.ok,
    emailError: mailResult.ok ? undefined : (mailResult.reason || 'unknown'),
    emailErrorFull: mailResult.ok ? undefined : (mailResult.error || undefined),
    message: mailResult.ok
      ? 'We sent a 6-digit verification code to your email. Check your inbox (and Spam folder).'
      : 'A 6-digit verification code was generated. Check the server console log for "[mail][code]" to get your code, or check your Gmail inbox.',
  });
});

app.post('/api/verify-otp', (req, res) => {
  const { username, email, code } = req.body;
  const handle = String(username || email || '').trim();
  if (!handle) {
    return res.status(400).json({ error: 'Username or email is required' });
  }
  const submitted = String(code || '').trim();
  if (!/^\d{6}$/.test(submitted)) {
    return res.status(400).json({ error: 'Enter the 6-digit code sent to your email' });
  }

  const users = loadData(usersFile);
  const user = findUserByHandle(users, handle);
  if (!user) return res.status(404).json({ error: 'Account not found' });

  const check = isValidOtpForUser(user, submitted);
  if (!check.ok) {
    switch (check.code) {
      case 'ALREADY_VERIFIED':
        return res.status(400).json({ error: 'This account is already verified. Please log in.' });
      case 'NO_CODE':
        return res.status(400).json({ error: 'No verification code is pending. Tap "Resend code" first.' });
      case 'EXPIRED':
        return res.status(410).json({ error: 'This code has expired. Tap "Resend code" to get a new one.' });
      case 'WRONG_CODE':
      default:
        return res.status(401).json({ error: 'Incorrect code. Double-check the email (and Spam folder) or tap "Resend code".' });
    }
  }

  user.isVerified = true;
  user.verificationOtp = undefined;
  user.verificationOtpExpiry = undefined;
  user.verificationOtpLastSent = undefined;
  user.verificationToken = undefined;
  user.verificationTokenExpiry = undefined;
  saveData(usersFile, users);

  return res.json({
    ok: true,
    message: 'Email verified successfully! You can now log in.',
    user: toPublicUser(user),
  });
});

app.post('/api/resend-otp', async (req, res) => {
  const { username, email } = req.body;
  const handle = String(username || email || '').trim();
  if (!handle) {
    return res.status(400).json({ error: 'Username or email is required' });
  }

  const users = loadData(usersFile);
  const user = findUserByHandle(users, handle);
  if (!user) return res.status(404).json({ error: 'Account not found. Please register first.' });
  if (user.isVerified === true) {
    return res.status(400).json({ error: 'This account is already verified. Please log in.' });
  }

  const now = Date.now();
  const lastSent = parseInt(user.verificationOtpLastSent || '0', 10);
  const tooSoon = lastSent && (now - lastSent) < OTP_RESEND_COOLDOWN_MS;
  if (tooSoon) {
    const waitSec = Math.max(1, Math.ceil((OTP_RESEND_COOLDOWN_MS - (now - lastSent)) / 1000));
    return res.status(429).json({
      error: `Please wait ${waitSec}s before requesting a new code.`,
      retryAfterSec: waitSec,
    });
  }

  if (!user.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(user.email)) {
    return res.status(400).json({ error: 'This account has no valid email address on file. Contact the school admin.' });
  }

  const otp = generateOtp();
  setUserOtp(user, otp, now);
  saveData(usersFile, users);

  let mailResult = { ok: false, reason: 'skipped' };
  try {
    mailResult = await sendEmailCode({
      toEmail: user.email,
      otp,
      username: user.fullName || user.username,
    });
  } catch (err) {
    console.error('[resend-otp][mail] Error:', err);
    mailResult = { ok: false, reason: 'exception', error: String(err?.message || err), otp };
  }

  return res.json({
    messageCode: 'EMAIL_VERIFICATION_REQUIRED',
    message: mailResult.ok
      ? 'A new verification code has been emailed to you.'
      : 'A new code was generated (check the server console). Also check your Spam folder.',
    email: user.email,
    expiresInMs: OTP_EXPIRY_MS,
    emailSent: mailResult.ok,
    emailError: mailResult.ok ? undefined : (mailResult.reason || 'unknown'),
  });
});

// Self-service password reset from login screen (non-admin only).
app.post('/api/reset-password', async (req, res) => {
  const { username, newPassword } = req.body;
  if (!username || !newPassword) {
    return res.status(400).json({ error: 'Username/email and new password are required' });
  }
  if (!isStrongPassword(newPassword)) {
    return res.status(400).json({
      error: 'Password must be at least 8 characters long, contain at least one uppercase letter, one lowercase letter, one digit, and one special character (!@#$%^&*)',
    });
  }

  const users = loadData(usersFile);
  const user = findUserByHandle(users, username);
  const idx = user ? users.findIndex(u => u.id === user.id) : -1;
  if (idx === -1) return res.status(404).json({ error: 'Account not found' });
  if (users[idx].role === 'admin') {
    return res.status(403).json({ error: 'Admin password reset is restricted. Use admin panel.' });
  }

  const hashedPassword = await hashPassword(newPassword);
  users[idx].password = hashedPassword;
  saveData(usersFile, users);
  return res.json({ message: 'Password reset successful' });
});

// Login
app.post('/api/login', async (req, res) => {
  const { username, password, loginMode } = req.body;
  const modeRaw = typeof loginMode === 'string' ? loginMode.trim() : 'auto';
  const mode = ['auto', 'username', 'email', 'studentId'].includes(modeRaw) ? modeRaw : 'auto';
  let users = loadData(usersFile);
  let user = findUserByHandle(users, username, mode);

  // Safety fallback: if default admin is missing in persisted data, recreate it.
  if (!user && String(username).toLowerCase() === String(DEFAULT_ADMIN_USERNAME).toLowerCase() && (mode === 'auto' || mode === 'username')) {
    const hashedPassword = await hashPassword(DEFAULT_ADMIN_PASSWORD);
    users.push({
      id: uuidv4(),
      username: DEFAULT_ADMIN_USERNAME,
      password: hashedPassword,
      role: 'admin',
      fullName: DEFAULT_ADMIN_FULLNAME,
      studentId: '',
      course: '',
      section: '',
      isApproved: true,
      isVerified: true,
    });
    saveData(usersFile, users);
    user = findUserByHandle(users, username, mode);
  }

  if (!user) {
    let msg = 'Student ID, email, or username not found';
    if (mode === 'email') msg = 'No account found with that email address';
    else if (mode === 'studentId') msg = 'No account found with that Student ID';
    else if (mode === 'username') msg = 'Username not found';
    return res.status(401).json({ error: msg });
  }
  if (user.isVerified !== true) {
    // For STUDENT accounts: keep email-verification gate open. Try to auto-generate
    // a fresh OTP + auto-send if (a) none is pending or (b) previous one expired, so the
    // UI can present the OTP dialog to the user without an extra resend tap.
    if (user.role === 'student' && user.email) {
      const now = Date.now();
      const currentExpiry = parseInt(user.verificationOtpExpiry || '0', 10);
      const hasValidPending = Boolean(user.verificationOtp) && currentExpiry && currentExpiry > now;
      if (!hasValidPending) {
        const lastSent = parseInt(user.verificationOtpLastSent || '0', 10);
        const cooldownPassed = !lastSent || (now - lastSent) >= OTP_RESEND_COOLDOWN_MS;
        if (cooldownPassed) {
          const otp = generateOtp();
          setUserOtp(user, otp, now);
          saveData(usersFile, users);
          let mailResult = { ok: false, reason: 'skipped' };
          try {
            mailResult = await sendEmailCode({
              toEmail: user.email,
              otp,
              username: user.fullName || user.username,
            });
          } catch (err) {
            console.error('[login][mail] Error:', err);
          }
          return res.status(403).json({
            error: 'Email not verified',
            messageCode: 'EMAIL_VERIFICATION_REQUIRED',
            message: mailResult.ok
              ? 'We emailed a 6-digit code — enter it below to activate your account.'
              : 'Enter the 6-digit verification code (check the server console or your email) to activate your account.',
            username: user.username,
            email: user.email,
            expiresInMs: OTP_EXPIRY_MS,
            emailSent: mailResult.ok,
          });
        }
      }
    }
    return res.status(403).json({
      error: user.role === 'faculty'
        ? 'Account pending admin approval'
        : 'Email not verified',
      messageCode: user.role === 'student' ? 'EMAIL_VERIFICATION_REQUIRED' : 'PENDING_ADMIN_APPROVAL',
      username: user.username,
      email: user.email || '',
    });
  }
  const passwordMatch = await comparePassword(password, user.password);
  if (!passwordMatch) return res.status(401).json({ error: 'Wrong password' });
  if (!isFacultyApproved(user)) {
    return res.status(403).json({ error: 'Faculty account is pending admin approval' });
  }
  
  const token = jwt.sign({ id: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: '24h' });
  res.json({
    token,
    user: toPublicUser(user),
  });
});

app.get('/api/me', authenticateToken, (req, res) => {
  const users = loadData(usersFile);
  const account = users.find((u) => u.id === req.user.id);
  if (!account) return res.status(404).json({ error: 'Account not found' });
  res.json({ user: toPublicUser(account) });
});

// Events
app.get('/api/events', authenticateToken, (req, res) => {
  const events = loadData(eventsFile);
  res.json(events);
});

const MAX_POSTER_CHARS = 1_500_000; // ~1.5MB base64 ≈ 1.1MB raw image (safe cap for Render)
const MAX_DESC_CHARS = 5000;

app.post('/api/events', authenticateToken, requireAdmin, (req, res) => {
  const events = loadData(eventsFile);
  const { name, date, status, startAt, endAt, description, posterImageUrl } = req.body;
  if (!name || !date) return res.status(400).json({ error: 'Invalid payload' });
  if (typeof posterImageUrl === 'string' && posterImageUrl.trim().length > MAX_POSTER_CHARS) {
    return res.status(413).json({
      error: 'Poster image too large',
      message: 'The poster image exceeds the 1.5MB limit after encoding. Choose a smaller photo or reduce quality.',
      maxSizeMb: 1.5,
    });
  }
  if (typeof description === 'string' && description.length > MAX_DESC_CHARS) {
    return res.status(400).json({
      error: 'Description too long',
      message: `Event description is ${description.length} chars. Limit is ${MAX_DESC_CHARS}.`,
    });
  }
  const cleanPoster = (typeof posterImageUrl === 'string' && posterImageUrl.trim().length <= MAX_POSTER_CHARS)
    ? posterImageUrl.trim()
    : '';
  const cleanDesc = (typeof description === 'string' && description.length <= MAX_DESC_CHARS)
    ? description.trim()
    : (description ?? '').toString().trim().slice(0, MAX_DESC_CHARS);
  const event = {
    id: uuidv4(),
    name,
    date,
    status: ['draft', 'open', 'closed'].includes(status) ? status : 'open',
    startAt: startAt || null,
    endAt: endAt || null,
    description: cleanDesc,
    posterImageUrl: cleanPoster,
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
  const { name, date, status, startAt, endAt, description, posterImageUrl } = req.body;
  if (typeof posterImageUrl === 'string' && posterImageUrl.trim().length > MAX_POSTER_CHARS) {
    return res.status(413).json({
      error: 'Poster image too large',
      message: 'The poster image exceeds the 1.5MB limit after encoding. Choose a smaller photo or reduce quality.',
      maxSizeMb: 1.5,
    });
  }
  if (typeof description === 'string' && description.length > MAX_DESC_CHARS) {
    return res.status(400).json({
      error: 'Description too long',
      message: `Event description is ${description.length} chars. Limit is ${MAX_DESC_CHARS}.`,
    });
  }
  if (name != null) events[idx].name = name;
  if (date != null) events[idx].date = date;
  if (status != null && ['draft', 'open', 'closed'].includes(status)) events[idx].status = status;
  events[idx].startAt = startAt || null;
  events[idx].endAt = endAt || null;
  if (typeof description === 'string') events[idx].description = description.trim().slice(0, MAX_DESC_CHARS);
  if (typeof posterImageUrl === 'string' && posterImageUrl.trim().length <= MAX_POSTER_CHARS) {
    events[idx].posterImageUrl = posterImageUrl.trim();
  }
  saveData(eventsFile, events);
  res.json(events[idx]);
});

app.get('/api/faculty', authenticateToken, (req, res) => {
  const users = loadData(usersFile)
    .filter((u) => u.role === 'faculty' && isFacultyApproved(u))
    .map(toPublicUser);
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
    // Faculty sees:
    // 1) open check-ins handled by this faculty
    // 2) closed records checked out by this faculty
    return res.json(
      all.filter(a => {
        if (!a.checkOutAt) {
          return a.checkedInByFacultyId === req.user.id;
        }
        return a.checkedOutByFacultyId === req.user.id;
      }),
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
  const users = loadData(usersFile).map(toPublicUser);
  res.json(users);
});

app.post('/api/users', authenticateToken, requireAdmin, async (req, res) => {
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
  if (hasDuplicateStudentId(users, studentId)) {
    return res.status(400).json({ error: 'This ID is already have' });
  }
  const hashedPassword = await hashPassword(String(password));
  const u = {
    id: uuidv4(),
    username,
    password: hashedPassword,
    role,
    fullName: fullName || '',
    studentId: studentId || '',
    course: course || '',
    section: section || '',
    isApproved: true,
    isVerified: true,
  };
  users.push(u);
  saveData(usersFile, users);
  res.json(toPublicUser(u));
});

app.patch('/api/users/:id', authenticateToken, requireAdmin, async (req, res) => {
  const users = loadData(usersFile);
  const idx = users.findIndex(u => u.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  const isSelfUpdate = req.user && req.user.id === req.params.id;

  const current = users[idx];
  const next = { ...current };
  const {
    id: nextIdRaw,
    username,
    password,
    role,
    fullName,
    studentId,
    course,
    section,
    isApproved,
  } = req.body || {};

  const nextId = nextIdRaw == null ? current.id : String(nextIdRaw).trim();
  if (isSelfUpdate && nextId !== current.id) {
    return res.status(400).json({ error: 'You cannot change your own user ID' });
  }
  if (!nextId) return res.status(400).json({ error: 'User ID is required' });
  if (hasDuplicateUserId(users, nextId, current.id)) {
    return res.status(400).json({ error: 'User ID already exists' });
  }
  next.id = nextId;

  if (username != null) {
    const normalizedUsername = String(username).trim();
    if (!normalizedUsername) return res.status(400).json({ error: 'Username is required' });
    if (users.some((u) => u.id !== current.id && String(u.username).toLowerCase() === normalizedUsername.toLowerCase())) {
      return res.status(400).json({ error: 'Username already exists' });
    }
    next.username = normalizedUsername;
  }

  if (role != null) {
    if (!['student', 'admin', 'faculty'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }
    if (current.role !== 'faculty' && role === 'faculty') {
      next.isApproved = true;
    }
    if (role !== 'faculty') {
      next.isApproved = true;
    }
    next.role = role;
  }

  if (fullName != null) next.fullName = String(fullName).trim();
  if (studentId != null) next.studentId = String(studentId).trim();
  if (course != null) next.course = String(course).trim();
  if (section != null) next.section = String(section).trim();
  if (password != null) {
    if (!String(password)) return res.status(400).json({ error: 'Password is required' });
    next.password = await hashPassword(String(password));
  }
  if (isApproved != null) {
    if (next.role !== 'faculty' && Boolean(isApproved) == false) {
      return res.status(400).json({ error: 'Only faculty can be unapproved' });
    }
    next.isApproved = Boolean(isApproved);
  }
  if (next.role === 'faculty' && next.isApproved == null) {
    next.isApproved = isFacultyApproved(current);
  }
  if (next.role !== 'faculty') {
    next.isApproved = true;
  }

  if (hasDuplicateStudentId(users, next.studentId, current.id)) {
    return res.status(400).json({ error: 'This ID is already have' });
  }

  if (next.role === 'student') {
    if (!next.fullName || !next.studentId || !next.course || !next.section) {
      return res.status(400).json({ error: 'Full name, student ID, course, and section are required' });
    }
  }

  users[idx] = next;

  // Keep attendance ownership consistent when admin edits IDs/student IDs.
  if (next.id !== current.id || next.studentId !== current.studentId) {
    const attendance = loadData(attendanceFile);
    let changed = false;
    for (const a of attendance) {
      if (next.id !== current.id) {
        if (a.userId === current.id) {
          a.userId = next.id;
          changed = true;
        }
        if (a.checkedInByFacultyId === current.id) {
          a.checkedInByFacultyId = next.id;
          changed = true;
        }
        if (a.checkedOutByFacultyId === current.id) {
          a.checkedOutByFacultyId = next.id;
          changed = true;
        }
      }
      if (next.studentId !== current.studentId && next.studentId) {
        if (a.userId === next.id || a.userId === current.id) {
          a.studentId = next.studentId;
          changed = true;
        }
      }
    }
    if (changed) saveData(attendanceFile, attendance);
  }

  saveData(usersFile, users);
  const u = users[idx];
  res.json(toPublicUser(u));
});

app.post('/api/users/:id/reset-password', authenticateToken, requireAdmin, async (req, res) => {
  const { newPassword } = req.body;
  if (!newPassword) return res.status(400).json({ error: 'New password is required' });
  if (String(newPassword).length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }

  const users = loadData(usersFile);
  const idx = users.findIndex((u) => u.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  users[idx].password = await hashPassword(String(newPassword));
  saveData(usersFile, users);
  return res.json({ message: 'Password reset successful' });
});

app.delete('/api/users/:id', authenticateToken, requireAdmin, (req, res) => {
  if (req.user && req.user.id === req.params.id) {
    return res.status(400).json({ error: 'You cannot delete your own account' });
  }
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

const ensureAllPasswordsHashed = async () => {
  const users = loadData(usersFile);
  let changed = false;
  for (const u of users) {
    if (u.password == null) continue;
    const pw = String(u.password);
    // bcrypt hashes are exactly ~60 chars and always start with $2
    if (pw.length < 20 || !pw.startsWith('$2')) {
      u.password = await hashPassword(pw || String(DEFAULT_ADMIN_PASSWORD));
      changed = true;
    }
    // Ensure all accounts have a sensible isVerified field
    if (u.isVerified !== true && u.isVerified !== false) {
      u.isVerified = true;
      changed = true;
    }
    if (u.isApproved !== true && u.isApproved !== false && u.role === 'faculty') {
      u.isApproved = false;
      changed = true;
    }
    if (u.isApproved !== true && u.isApproved !== false && u.role !== 'faculty') {
      u.isApproved = true;
      changed = true;
    }
  }
  if (changed) saveData(usersFile, users);
};

const start = async () => {
  try {
    await initializeMongoMirror();
  } catch (err) {
    console.error('[mongo] Initialization wrapper error, continuing with file storage:', err?.message || err);
  }
  await ensureAllPasswordsHashed();
  await ensureDefaultAdmin();
  app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log('═══════════════════════════════════════════════════════════════');
    console.log(`🚀  Server running at http://localhost:${PORT}`);
    console.log(`🔗  Public endpoint: https://school-event-managements.onrender.com`);
    console.log(`💾  Data layer:      ${mongoDb ? `MongoDB ("${MONGODB_DB_NAME}") ✅ PERSISTENT` : 'JSON files (not persistent on Render ⚠️)'}`);
    const activeTransports = [];
    if (BREVO_API_KEY) {
      const sender = BREVO_SENDER_EMAIL || GMAIL_USER || 'NOT_SET';
      activeTransports.push(`Brevo HTTPS API (sender=${sender}) ✅ — works on Render Free`);
    }
    if (GMAIL_USER && GMAIL_APP_PASSWORD) {
      activeTransports.push(`Gmail SMTP 587 STARTTLS (from=${GMAIL_USER}) — needs egress (not Render Free)`);
    }
    if (activeTransports.length === 0) {
      activeTransports.push('None configured. OTPs logged ONLY to server console ⚠️');
    }
    console.log(`📧  Email delivery:  ${activeTransports.join('  |  ')}`);
    console.log(`🔐  JWT secret:      ${JWT_SECRET === 'school-event-secret-key-change-in-prod' ? '⚠️  USING DEFAULT (override JWT_SECRET env var!)' : 'Set via env var ✅'}`);
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('');
  });
};

start();
