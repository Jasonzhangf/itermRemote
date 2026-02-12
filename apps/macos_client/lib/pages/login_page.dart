import "package:flutter/material.dart";
import "../services/auth_service.dart";

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({Key? key, required this.onLoginSuccess}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AuthService.instance.tokenExpired.listen((_) {
      if (mounted) {
        setState(() {
          _errorMessage = "登录已过期，请重新登录";
        });
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isRegisterMode) {
        final result = await AuthService.instance.register(
          _usernameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text,
          _nicknameController.text.trim(),
        );

        if (!result.success) {
          setState(() => _errorMessage = result.error);
          return;
        }

        if (!mounted) return;
        
        // 注册成功：清空字段，切换到登录模式
        _emailController.clear();
        _nicknameController.clear();
        _passwordController.clear();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("注册成功，请登录")),
        );
        setState(() => _isRegisterMode = false);
      } else {
        final result = await AuthService.instance.login(
          _usernameController.text.trim(),
          _passwordController.text,
        );

        if (!result.success) {
          setState(() => _errorMessage = result.error);
          return;
        }

        widget.onLoginSuccess();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 顶部 Logo 区域
                        Icon(
                          Icons.devices,
                          size: 64,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "ItermRemote",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          _isRegisterMode ? "创建账号" : "登录到您的账号",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        
                        // 错误提示
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, 
                                     color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.orange.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 32),
                        
                        // 表单区域
                        Form(
                          key: _formKey,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: const InputDecoration(
                                    labelText: "用户名",
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.person),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "请输入用户名";
                                    }
                                    if (value.trim().length < 3) {
                                      return "用户名至少3个字符";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                
                                if (_isRegisterMode) ...[
                                  TextFormField(
                                    controller: _emailController,
                                    decoration: const InputDecoration(
                                      labelText: "邮箱",
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.email),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return "请输入邮箱";
                                      }
                                      if (!value.contains("@")) {
                                        return "请输入有效的邮箱地址";
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _nicknameController,
                                    decoration: const InputDecoration(
                                      labelText: "昵称",
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.badge),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return "请输入昵称";
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: "密码",
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.lock),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "请输入密码";
                                    }
                                    if (_isRegisterMode && value.length < 6) {
                                      return "密码至少6个字符";
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const Spacer(),
                        
                        // 底部按钮区域 - 固定在底部
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(_isRegisterMode ? "注册" : "登录"),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(() => _isRegisterMode = !_isRegisterMode),
                                child: Text(_isRegisterMode ? "已有账号？登录" : "没有账号？注册"),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
