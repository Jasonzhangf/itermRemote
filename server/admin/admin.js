const AdminJS = require('adminjs');
const AdminJSExpress = require('@adminjs/express');
const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const API_URL = process.env.API_URL || 'http://127.0.0.1:8080';

// 简单的内存数据存储（实际生产应使用数据库）
const resources = [
  {
    resource: {
      id: 'users',
      name: '用户管理',
      schema: {
        id: { type: 'string', isId: true },
        username: { type: 'string', isTitle: true },
        email: { type: 'string' },
        nickname: { type: 'string' },
        role: { type: 'string' },
        created_at: { type: 'date' },
      },
    },
    options: {
      navigation: { name: '用户管理', icon: 'User' },
      properties: {
        id: { isVisible: false },
        username: { isTitle: true },
        role: { availableValues: [{ value: 'user', label: '普通用户' }, { value: 'admin', label: '管理员' }] },
      },
      actions: {
        list: { isAccessible: true },
        show: { isAccessible: true },
        edit: { isAccessible: true },
        delete: { isAccessible: true },
        new: { isAccessible: false },
      },
    },
  },
];

const adminJs = new AdminJS({
  resources,
  rootPath: '/admin',
  branding: {
    companyName: 'ItermRemote 管理后台',
    softwareBrothers: false,
  },
  dashboard: {
    component: AdminJS.bundle('./dashboard'),
  },
});

const router = AdminJSExpress.buildRouter(adminJs);

app.use(adminJs.rootPath, router);

// API 代理路由
app.get('/api/users', async (req, res) => {
  try {
    const token = req.headers.authorization;
    const response = await fetch(`${API_URL}/api/v1/user/profile`, {
      headers: { 'Authorization': token },
    });
    if (response.ok) {
      const data = await response.json();
      res.json([data]);
    } else {
      res.status(401).json({ error: 'Unauthorized' });
    }
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`AdminJS ready on http://localhost:${PORT}/admin`);
  console.log(`API Backend: ${API_URL}`);
});
