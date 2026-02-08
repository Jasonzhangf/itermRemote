import express from 'express';
import session from 'express-session';
import fetch from 'node-fetch';
import { Sequelize, DataTypes } from 'sequelize';

const app = express();
app.use(express.json());

const API_URL = process.env.API_URL || 'http://api-server:8080';
const ADMIN_RESET_PASSWORD = process.env.ADMIN_RESET_PASSWORD || 'Admin123!';
const ADMIN_COOKIE_SECRET = process.env.ADMIN_COOKIE_SECRET || 'change-me-admin-cookie';

const DB_HOST = process.env.DB_HOST || 'postgres';
const DB_PORT = process.env.DB_PORT || '5432';
const DB_USER = process.env.DB_USER || 'itermremote';
const DB_PASSWORD = process.env.DB_PASSWORD || 'itermremote';
const DB_NAME = process.env.DB_NAME || 'itermremote';

const sequelize = new Sequelize(`postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}`, {
  logging: false,
});

const User = sequelize.define('User', {
  id: { type: DataTypes.UUID, primaryKey: true },
  username: { type: DataTypes.STRING },
  password_hash: { type: DataTypes.STRING },
  email: { type: DataTypes.STRING },
  nickname: { type: DataTypes.STRING },
  role: { type: DataTypes.STRING },
  status: { type: DataTypes.SMALLINT },
  created_at: { type: DataTypes.DATE },
  updated_at: { type: DataTypes.DATE },
}, {
  tableName: 'users',
  timestamps: false,
  underscored: true,
});

const sessions = new Map();

const authenticate = async (username, password) => {
  try {
    const res = await fetch(`${API_URL}/api/v1/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) return null;
    const data = await res.json();

    const profileRes = await fetch(`${API_URL}/api/v1/user/profile`, {
      headers: { Authorization: `Bearer ${data.access_token}` },
    });
    if (!profileRes.ok) return null;
    const profile = await profileRes.json();
    if (profile.role !== 'admin') return null;

    return { username, token: data.access_token, role: profile.role, userId: profile.id };
  } catch (err) {
    console.error('[Admin] Auth error:', err.message);
    return null;
  }
};

app.use(session({
  secret: ADMIN_COOKIE_SECRET,
  resave: false,
  saveUninitialized: true,
  cookie: { maxAge: 86400000 }
}));

app.get('/', (req, res) => res.redirect('/admin'));

app.get('/admin', (req, res) => {
  if (!req.session.admin) {
    return res.send(`<!DOCTYPE html>
<html>
<head><title>ItermRemote Admin</title><style>
body{font-family:sans-serif;max-width:400px;margin:50px auto;padding:20px}
input{width:100%;padding:10px;margin:10px 0;box-sizing:border-box}
button{width:100%;padding:12px;background:#4CAF50;color:white;border:none;cursor:pointer}
button:hover{background:#45a049}
</style></head>
<body>
  <h1>ItermRemote 管理后台</h1>
  <form method="POST" action="/admin/login">
    <input name="username" placeholder="用户名" required>
    <input name="password" type="password" placeholder="密码" required>
    <button type="submit">登录</button>
  </form>
</body></html>`);
  }
  res.redirect('/admin/dashboard');
});

app.post('/admin/login', express.urlencoded({ extended: true }), async (req, res) => {
  const { username, password } = req.body;
  const admin = await authenticate(username, password);
  if (!admin) return res.status(401).send('登录失败');
  req.session.admin = admin;
  res.redirect('/admin/dashboard');
});

app.get('/admin/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/admin');
});

app.get('/admin/dashboard', async (req, res) => {
  if (!req.session.admin) return res.redirect('/admin');
  
  let users = [];
  try {
    const usersList = await User.findAll({
      attributes: ['id', 'username', 'email', 'nickname', 'role', 'status', 'created_at'],
      order: [['created_at', 'DESC']],
      limit: 100
    });
    users = usersList.map(u => u.toJSON());
  } catch (e) {
    console.error('[Admin] Fetch users error:', e.message);
    return res.status(500).send('数据库错误: ' + e.message);
  }
  
  const userRows = users.map(u => `
    <tr>
      <td>${u.username}</td>
      <td>${u.email || '-'}</td>
      <td>${u.nickname || '-'}</td>
      <td><span class="role-${u.role}">${u.role}</span></td>
      <td>${u.status === 1 ? '<span class="status-active">活跃</span>' : '<span class="status-inactive">禁用</span>'}</td>
      <td>${new Date(u.created_at).toLocaleDateString()}</td>
      <td>
        <form method="POST" action="/admin/reset-password" style="display:inline">
          <input type="hidden" name="userId" value="${u.id}">
          <button type="submit" class="btn-reset" onclick="return confirm('确定重置密码为 ${ADMIN_RESET_PASSWORD} ?')">重置密码</button>
        </form>
      </td>
    </tr>
  `).join('');
  
  res.send(`<!DOCTYPE html>
<html>
<head>
  <title>ItermRemote Admin</title>
  <style>
    body{font-family:sans-serif;padding:20px;max-width:1200px;margin:0 auto}
    .header{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #ddd;padding:12px;text-align:left}
    th{background:#4CAF50;color:white}
    tr:nth-child(even){background:#f2f2f2}
    tr:hover{background:#ddd}
    button{padding:6px 12px;cursor:pointer;border:none;background:#ff9800;color:white;border-radius:3px}
    button:hover{background:#e68900}
    .btn-reset{background:#2196F3}
    .btn-reset:hover{background:#1976D2}
    .role-admin{color:#f44336;font-weight:bold}
    .role-user{color:#4CAF50}
    .status-active{color:#4CAF50}
    .status-inactive{color:#f44336}
    .logout{color:#666;text-decoration:none}
    .logout:hover{color:#f44336}
  </style>
</head>
<body>
  <div class="header">
    <h1>ItermRemote 用户管理</h1>
    <div>当前用户: <b>${req.session.admin.username}</b> | <a href="/admin/logout" class="logout">退出</a></div>
  </div>
  <table>
    <tr><th>用户名</th><th>邮箱</th><th>昵称</th><th>角色</th><th>状态</th><th>创建时间</th><th>操作</th></tr>
    ${userRows}
  </table>
</body></html>`);
});

app.post('/admin/reset-password', express.urlencoded({ extended: true }), async (req, res) => {
  if (!req.session.admin) return res.status(401).send('未登录');
  const { userId } = req.body;
  const token = req.session.admin.token;
  
  try {
    const resetRes = await fetch(`${API_URL}/api/v1/admin/reset-password`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({ user_id: userId, new_password: ADMIN_RESET_PASSWORD }),
    });
    
    if (!resetRes.ok) {
      const err = await resetRes.json().catch(() => ({}));
      return res.status(500).send(`重置失败: ${err.error || resetRes.status}`);
    }
    
    res.send(`<!DOCTYPE html>
<html><head><style>
body{font-family:sans-serif;max-width:400px;margin:50px auto;text-align:center}
.success{color:#4CAF50;font-size:48px}
</style></head><body>
  <div class="success">✓</div>
  <h2>密码已重置</h2>
  <p>新密码: <b>${ADMIN_RESET_PASSWORD}</b></p>
  <a href="/admin/dashboard">返回用户列表</a>
</body></html>`);
  } catch (e) {
    res.status(500).send(`错误: ${e.message}`);
  }
});

const port = process.env.ADMIN_PORT || 3000;
app.listen(port, () => {
  console.log(`[Admin Simple] running on :${port}`);
});
