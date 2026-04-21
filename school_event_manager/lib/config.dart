const int attendanceTimeoutMinutes = 60;

const String apiBaseUrlDefault = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

const bool lockServerSettings = bool.fromEnvironment(
  'LOCK_SERVER_SETTINGS',
  defaultValue: false,
);
