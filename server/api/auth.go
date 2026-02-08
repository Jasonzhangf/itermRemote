package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/argon2"
)

var jwtSecret = []byte(getEnv("JWT_SECRET", "changeme-insecure-secret-key"))

// Claims JWT 声明
type Claims struct {
	UserID      string `json:"sub"`
	Username    string `json:"username"`
	IPv6Capable bool   `json:"ipv6_capable"`
	DeviceID    string `json:"device_id"`
	jwt.RegisteredClaims
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=32"`
	Password string `json:"password" binding:"required,min=8"`
	Email    string `json:"email" binding:"required,email"`
	Nickname string `json:"nickname" binding:"max=64"`
}

// LoginRequest 登录请求
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	DeviceID string `json:"device_id"`
	IPv6     string `json:"ipv6"`
}

// RefreshTokenRequest Token 刷新请求
type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Register 用户注册
func Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// 检查用户名是否存在
	var existingUser User
	if err := db.Where("username = ?", req.Username).First(&existingUser).Error; err == nil {
		c.JSON(400, gin.H{"error": "username already exists"})
		return
	}

	// 创建用户
	passwordHash := hashPassword(req.Password)
	user := User{
		Username:     req.Username,
		PasswordHash: passwordHash,
		Email:        req.Email,
		Nickname:     req.Nickname,
		Status:       1,
	}

	if err := db.Create(&user).Error; err != nil {
		c.JSON(500, gin.H{"error": "failed to create user"})
		return
	}

	// 生成 Token
	accessToken, refreshToken, err := generateTokens(user.ID.String(), user.Username, "", false)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to generate tokens"})
		return
	}

	// 保存 Session
	saveSession(user.ID.String(), "", accessToken, refreshToken, c.ClientIP(), "")

	c.JSON(201, gin.H{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"token_type":    "Bearer",
		"user": gin.H{
			"id":       user.ID,
			"username": user.Username,
			"nickname": user.Nickname,
		},
	})
}

// Login 用户登录
func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// 查找用户
	var user User
	if err := db.Where("username = ?", req.Username).First(&user).Error; err != nil {
		c.JSON(401, gin.H{"error": "invalid credentials"})
		return
	}

	// 验证密码
	if !verifyPassword(user.PasswordHash, req.Password) {
		c.JSON(401, gin.H{"error": "invalid credentials"})
		return
	}

	// 检查账号状态
	if user.Status != 1 {
		c.JSON(403, gin.H{"error": "account disabled"})
		return
	}

	// 更新最后登录信息
	now := time.Now()
	updates := map[string]interface{}{
		"last_login_at": now,
	}
	if req.IPv6 != "" {
		updates["last_ipv6"] = req.IPv6
		updates["ipv6_verified"] = true
	}
	db.Model(&user).Updates(updates)

	// 更新设备信息
	if req.DeviceID != "" {
		updateDevice(user.ID.String(), req.DeviceID, c.ClientIP(), req.IPv6)
	}

	// 生成 Token
	ipv6Capable := req.IPv6 != ""
	accessToken, refreshToken, err := generateTokens(user.ID.String(), user.Username, req.DeviceID, ipv6Capable)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to generate tokens"})
		return
	}

	// 保存 Session
	saveSession(user.ID.String(), req.DeviceID, accessToken, refreshToken, c.ClientIP(), req.IPv6)

	c.JSON(200, gin.H{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"token_type":    "Bearer",
		"user": gin.H{
			"id":       user.ID,
			"username": user.Username,
			"nickname": user.Nickname,
		},
	})
}

// RefreshToken 刷新 Token
func RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// 验证 Refresh Token
	tokenHash := hashToken(req.RefreshToken)
	var session Session
	if err := db.Where("refresh_token_hash = ? AND revoked_at IS NULL AND expires_at > ?", tokenHash, time.Now()).
		First(&session).Error; err != nil {
		c.JSON(401, gin.H{"error": "invalid or expired refresh token"})
		return
	}

	// 查找用户
	var user User
	if err := db.First(&user, "id = ?", session.UserID).Error; err != nil {
		c.JSON(401, gin.H{"error": "user not found"})
		return
	}

	// 生成新 Access Token
	accessToken, _, err := generateTokens(user.ID.String(), user.Username, session.DeviceID, false)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to generate token"})
		return
	}

	// 更新 Session
	accessTokenHash := hashToken(accessToken)
	db.Model(&session).Update("access_token_hash", accessTokenHash)

	c.JSON(200, gin.H{
		"access_token": accessToken,
		"token_type":   "Bearer",
	})
}

// JWTAuthMiddleware JWT 认证中间件
func JWTAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(401, gin.H{"error": "authorization header required"})
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.AbortWithStatusJSON(401, gin.H{"error": "invalid authorization header"})
			return
		}

		tokenString := parts[1]
		claims, err := validateToken(tokenString)
		if err != nil {
			c.AbortWithStatusJSON(401, gin.H{"error": "invalid token"})
			return
		}

		c.Set("claims", claims)
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}

// 辅助函数

func generateTokens(userID, username, deviceID string, ipv6Capable bool) (string, string, error) {
	now := time.Now()

	// Access Token (15 分钟)
	accessClaims := Claims{
		UserID:      userID,
		Username:    username,
		IPv6Capable: ipv6Capable,
		DeviceID:    deviceID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(15 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        uuid.New().String(),
		},
	}
	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessTokenString, err := accessToken.SignedString(jwtSecret)
	if err != nil {
		return "", "", err
	}

	// Refresh Token (7 天)
	refreshClaims := Claims{
		UserID:   userID,
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        uuid.New().String(),
		},
	}
	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString(jwtSecret)
	if err != nil {
		return "", "", err
	}

	return accessTokenString, refreshTokenString, nil
}

func validateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func hashPassword(password string) string {
	salt := []byte("itermremote-salt") // 生产环境应使用随机 salt
	hash := argon2.IDKey([]byte(password), salt, 1, 64*1024, 4, 32)
	return hex.EncodeToString(hash)
}

func verifyPassword(hash, password string) bool {
	return hashPassword(password) == hash
}

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func saveSession(userID, deviceID, accessToken, refreshToken, ip, ipv6 string) {
	session := Session{
		UserID:           uuid.MustParse(userID),
		DeviceID:         deviceID,
		AccessTokenHash:  hashToken(accessToken),
		RefreshTokenHash: hashToken(refreshToken),
		IP:               ip,
		IPv6:             ipv6,
		ExpiresAt:        time.Now().Add(7 * 24 * time.Hour),
	}
	db.Create(&session)
}

func updateDevice(userID, deviceID, ip, ipv6 string) {
	var device Device
	now := time.Now()

	// 查找或创建设备
	result := db.Where("user_id = ? AND device_id = ?", userID, deviceID).First(&device)
	if result.Error != nil {
		// 创建新设备
		device = Device{
			UserID:       uuid.MustParse(userID),
			DeviceID:     deviceID,
			LastIP:       ip,
			LastIPv6:     ipv6,
			SupportsIPv6: ipv6 != "",
			IsOnline:     true,
			LastSeenAt:   &now,
		}
		db.Create(&device)
	} else {
		// 更新设备
		updates := map[string]interface{}{
			"last_ip":     ip,
			"last_seen_at": now,
			"is_online":   true,
		}
		if ipv6 != "" {
			updates["last_ipv6"] = ipv6
			updates["supports_ipv6"] = true
		}
		db.Model(&device).Updates(updates)
	}
}

// GetUserProfile 获取用户信息
func GetUserProfile(c *gin.Context) {
	claims := c.MustGet("claims").(*Claims)

	var user User
	if err := db.First(&user, "id = ?", claims.UserID).Error; err != nil {
		c.JSON(404, gin.H{"error": "user not found"})
		return
	}

	c.JSON(200, gin.H{
		"id":            user.ID,
		"username":      user.Username,
		"email":         user.Email,
		"nickname":      user.Nickname,
		"ipv6_verified": user.IPv6Verified,
		"created_at":    user.CreatedAt,
		"role":         user.Role,
	})
}

// UpdateUserProfile 更新用户信息
func UpdateUserProfile(c *gin.Context) {
	claims := c.MustGet("claims").(*Claims)

	var req struct {
		Nickname string `json:"nickname"`
		Email    string `json:"email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{}
	if req.Nickname != "" {
		updates["nickname"] = req.Nickname
	}
	if req.Email != "" {
		updates["email"] = req.Email
	}

	if err := db.Model(&User{}).Where("id = ?", claims.UserID).Updates(updates).Error; err != nil {
		c.JSON(500, gin.H{"error": "failed to update profile"})
		return
	}

	c.JSON(200, gin.H{"status": "ok"})
}

// DeleteAccount 删除账号
func DeleteAccount(c *gin.Context) {
	claims := c.MustGet("claims").(*Claims)

	if err := db.Delete(&User{}, "id = ?", claims.UserID).Error; err != nil {
		c.JSON(500, gin.H{"error": "failed to delete account"})
		return
	}

	c.JSON(200, gin.H{"status": "ok"})
}
