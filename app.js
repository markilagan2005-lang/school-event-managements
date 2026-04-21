"use strict";

// Centralized School Event Manager with Auth & Backend API
const API_BASE = `${window.location.origin}/api`;

class EventManager {
    constructor() {
        this.token = localStorage.getItem('token');
        this.user = JSON.parse(localStorage.getItem('user')) || null;
        this.events = [];
        this.attendance = [];
        this.init();
    }

    init() {
        this.bindEvents();
        if (this.token) {
            this.showMainTabs();
            this.loadAllData();
        }
    }

    bindEvents() {
        // Login form
        document.getElementById('login-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.login();
        });

        // Register form
        document.getElementById('register-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.register();
        });

        // Toggle register
        document.getElementById('show-register').addEventListener('click', () => {
            document.getElementById('login-section').style.display = 'none';
            document.getElementById('register-section').style.display = 'block';
        });

        // Toggle login
        document.getElementById('show-login').addEventListener('click', () => {
            document.getElementById('register-section').style.display = 'none';
            document.getElementById('login-section').style.display = 'block';
        });

        // Logout
        document.getElementById('logout-btn')?.addEventListener('click', () => this.logout());

        // Event form
        document.getElementById('event-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.addEvent();
        });

        // Attendee form
        document.getElementById('attendee-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.addAttendee();
        });

        // Scanner
        document.getElementById('start-scan').addEventListener('click', () => this.startScanner());

        // Tabs
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('tab-btn')) {
                this.switchTab(e.target.dataset.tab);
            }
        });
    }

    async apiCall(endpoint, options = {}) {
        const headers = {
            'Content-Type': 'application/json',
            ...(this.token && { 'Authorization': `Bearer ${this.token}` })
        };
        const response = await fetch(`${API_BASE}${endpoint}`, {
            ...options,
            headers
        });
        if (!response.ok) {
            const error = await response.text();
            throw new Error(error);
        }
        return response.json();
    }

    async register() {
        const username = document.getElementById('register-username').value;
        const password = document.getElementById('register-password').value;
        const role = document.getElementById('register-role').value;
        try {
            const data = await this.apiCall('/register', {
                method: 'POST',
                body: JSON.stringify({ username, password, role })
            });
            this.token = data.token;
            this.user = data.user;
            localStorage.setItem('token', this.token);
            localStorage.setItem('user', JSON.stringify(this.user));
            document.getElementById('register-error').textContent = '';
            document.getElementById('username-display').textContent = `Welcome, ${this.user.username}!`;
            document.getElementById('user-info').style.display = 'block';
            this.showMainTabs();
            this.loadAllData();
        } catch (err) {
            document.getElementById('register-error').textContent = err.message || 'Register failed';
        }
    }

    async login() {
        const username = document.getElementById('login-username').value;
        const password = document.getElementById('login-password').value;
        try {
            const data = await this.apiCall('/login', {
                method: 'POST',
                body: JSON.stringify({ username, password })
            });
            this.token = data.token;
            this.user = data.user;
            localStorage.setItem('token', this.token);
            localStorage.setItem('user', JSON.stringify(this.user));
            document.getElementById('login-error').textContent = '';
            document.getElementById('username-display').textContent = `Welcome, ${this.user.username}!`;
            document.getElementById('user-info').style.display = 'block';
            this.showMainTabs();
            this.loadAllData();
        } catch (err) {
            document.getElementById('login-error').textContent = err.message || 'Login failed';
        }
    }

    logout() {
        this.token = null;
        this.user = null;
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        document.getElementById('user-info').style.display = 'none';
        document.getElementById('main-tabs').style.display = 'none';
        document.getElementById('login-lobby').style.display = 'block';
        document.getElementById('login-section').style.display = 'block';
        document.getElementById('register-section').style.display = 'none';
        document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        const dashboardBtn = document.querySelector('[data-tab="dashboard"]');
        if (dashboardBtn) dashboardBtn.classList.add('active');
        const dashboard = document.getElementById('dashboard');
        if (dashboard) dashboard.classList.add('active');
    }

    showMainTabs() {
        document.getElementById('main-tabs').style.display = 'flex';
        document.getElementById('login-lobby').style.display = 'none';
        document.getElementById('login-section').style.display = 'none';
        document.getElementById('register-section').style.display = 'none';
    }

    switchTab(tabName) {
        if (!this.token) {
            document.getElementById('login-lobby').style.display = 'block';
            return;
        }
        document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        const btn = document.querySelector(`[data-tab="${tabName}"]`);
        if (btn) btn.classList.add('active');
        const content = document.getElementById(tabName);
        if (content) content.classList.add('active');
        this.renderTab(tabName);
    }

    async renderTab(tabName) {
        switch(tabName) {
            case 'events':
                this.renderEvents();
                break;
            case 'attendees':
                this.renderAttendees();
                break;
            case 'scanner':
                this.renderEventSelect();
                break;
            case 'dashboard':
                this.renderDashboard();
                break;
        }
    }

    async loadAllData() {
        try {
            [this.events, this.attendance] = await Promise.all([
                this.apiCall('/events'),
                this.apiCall('/attendance')
            ]);
            this.renderAll();
        } catch (err) {
            console.error('Load failed:', err);
        }
    }

    renderAll() {
        this.renderEvents();
        this.renderAttendees();
        this.renderEventSelect();
    }

    async addEvent() {
        const name = document.getElementById('event-name').value;
        const date = document.getElementById('event-date').value;
        try {
            const event = await this.apiCall('/events', {
                method: 'POST',
                body: JSON.stringify({ name, date })
            });
            this.events.push(event);
            this.renderEvents();
            this.selectEventForAttendees(event.id, event.name);
            this.generateQR(event.id, event.name);
            document.getElementById('event-form').reset();
        } catch (err) {
            alert(err.message);
        }
    }

    async deleteEvent(id) {
        try {
            await this.apiCall(`/events/${id}`, { method: 'DELETE' });
            this.events = this.events.filter(e => e.id !== id);
            this.renderEvents();
        } catch (err) {
            alert(err.message);
        }
    }

    renderEvents() {
        const list = document.getElementById('events-list');
        if (!list) return;
        list.innerHTML = this.events.map(event => `
            <li>
                ${event.name} (${event.date}) - ${event.attendees?.length || 0} attendees
                <button onclick="eventManager.deleteEvent('${event.id}')">Delete</button>
            </li>
        `).join('') || '<li>No events</li>';
    }

    renderAttendees() {
        const list = document.getElementById('attendees-list');
        if (!list) return;
        list.innerHTML = this.events.map(event => `
            <li>
                <strong>${event.name}</strong>
                <button onclick="eventManager.selectEventForAttendees('${event.id}', '${event.name}')">Manage</button>
            </li>
        `).join('') || '<li>No events</li>';
    }

    selectEventForAttendees(eventId, name) {
        document.getElementById('attendee-form').dataset.eventId = eventId;
        const form = document.getElementById('attendee-form');
        let h3 = form.querySelector('h3');
        if (h3) h3.remove();
        form.insertAdjacentHTML('afterbegin', `<h3>${name}</h3>`);
    }

    async addAttendee() {
        const eventId = document.getElementById('attendee-form').dataset.eventId;
        if (!eventId) return alert('Select event');
        const event = this.events.find(e => e.id === eventId);
        this.generateQR(eventId, event ? event.name : eventId);
    }

    generateQR(eventId, eventName) {
        const qrData = JSON.stringify({ eventId });
        const canvas = document.getElementById('qr-canvas');
        document.getElementById('qr-canvas-container').style.display = 'block';
        const img = document.getElementById('qr-image');

        if (window.QRCode && typeof window.QRCode.toCanvas === 'function') {
            if (img) img.style.display = 'none';
            window.QRCode.toCanvas(canvas, qrData, { width: 200 });
        } else {
            if (canvas) canvas.style.display = 'none';
            fetch(`${API_BASE}/qr-image/${encodeURIComponent(eventId)}`)
                .then(r => r.json())
                .then(({ dataUrl }) => {
                    if (!img) return;
                    img.src = dataUrl;
                    img.style.display = 'block';
                })
                .catch(() => alert('Failed to generate QR. Check server and refresh.'));
        }
        document.getElementById('qr-text').textContent = `Event: ${eventName} (ID: ${eventId})`;
    }

    renderEventSelect() {
        const select = document.getElementById('scan-event-select');
        if (!select) return;
        select.innerHTML = '<option value="">Select Event</option>' + 
            this.events.map(e => `<option value="${e.id}">${e.name}</option>`).join('');
    }

    async startScanner() {
        const video = document.getElementById('video');
        const canvas = document.getElementById('canvas');
        const ctx = canvas.getContext('2d');
        const result = document.getElementById('scan-result');

        try {
            const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
            video.srcObject = stream;

            const tick = () => {
                canvas.width = video.videoWidth;
                canvas.height = video.videoHeight;
                ctx.drawImage(video, 0, 0);
                const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
                const code = jsQR(imageData.data, canvas.width, canvas.height);
                if (code) {
                    let data;
                    try {
                        data = JSON.parse(code.data);
                    } catch {
                        return requestAnimationFrame(tick);
                    }
                    if (!data || !data.eventId) return requestAnimationFrame(tick);
                    this.markAttendance({ eventId: data.eventId });
                    return;
                }
                requestAnimationFrame(tick);
            };
            tick();
        } catch (err) {
            result.textContent = 'Camera error: ' + err.message;
        }
    }

    async markAttendance(data) {
        const resultEl = document.getElementById('scan-result');
        try {
            const record = await this.apiCall('/attendance', {
                method: 'POST',
                body: JSON.stringify(data)
            });
            resultEl.innerHTML = `<span style="color:green;">✅ ${record.studentName} marked present!</span>`;
            this.attendance = await this.apiCall('/attendance');
            await this.renderDashboard();
        } catch (err) {
            resultEl.textContent = 'Error: ' + err.message;
        }
    }

    async renderDashboard() {
        const statsEl = document.getElementById('stats');
        const tbody = document.getElementById('attendance-table').querySelector('tbody');
        try {
            const stats = await this.apiCall('/attendance/stats');
            statsEl.innerHTML = `
                <div class="stat-card"><h3>${this.events.length}</h3><p>Events</p></div>
                <div class="stat-card"><h3>${stats.total}</h3><p>Total</p></div>
                <div class="stat-card"><h3>${stats.today}</h3><p>Today</p></div>
            `;
            tbody.innerHTML = this.attendance.slice(-20).reverse().map(r => `
                <tr>
                    <td>${r.eventName}</td>
                    <td>${r.studentName}</td>
                    <td>${r.studentId}</td>
                    <td class="status-present">PRESENT</td>
                    <td>${new Date(r.timestamp).toLocaleString()}</td>
                </tr>
            `).join('') || '<tr><td colspan=5>No records</td></tr>';
        } catch (err) {
            console.error(err);
        }
    }
}

const eventManager = new EventManager();

