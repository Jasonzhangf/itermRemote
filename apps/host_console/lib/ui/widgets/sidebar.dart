import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../pages/network_info_page.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // 用户信息卡片
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.account_circle, size: 48),
                const SizedBox(height: 8),
                Text(
                  AuthService.instance.currentUser?['username'] ?? '未登录',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  AuthService.instance.currentUser?['role'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 网络信息按钮
        ListTile(
          leading: const Icon(Icons.network_check),
          title: const Text('网络信息'),
          subtitle: const Text('查看 IPv4/IPv6 地址'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NetworkInfoPage()),
            );
          },
        ),
        
        const Divider(),
        
        // 登出按钮
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('登出'),
          onTap: () async {
            await AuthService.instance.logout();
          },
        ),
      ],
    );
  }
}
