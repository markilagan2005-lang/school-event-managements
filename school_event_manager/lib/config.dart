const int attendanceTimeoutMinutes = 60;

const String apiBaseUrlDefault = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://school-event-managements.onrender.com',
);

const bool lockServerSettings = bool.fromEnvironment(
  'LOCK_SERVER_SETTINGS',
  defaultValue: true,
);
