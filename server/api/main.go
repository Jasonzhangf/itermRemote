package main

import (
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var db *gorm.DB

func main() {
	// 初始化数据库
	var err error
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnv("DB_HOST", "localhost"),
		getEnv("DB_PORT", "5432"),
		getEnv("DB_USER", "itermremote"),
		getEnv("DB_PASSWORD", "itermremote"),
		getEnv("DB_NAME", "itermremote"),
	)

	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	log.Println("Database connected successfully")

	// 自动迁移
	if err := db.AutoMigrate(&User{}, &Device{}, &Session{}, &PasswordResetToken{}); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// 初始化 Redis
	initRedis()

	// 初始化路由
	router := gin.Default()

	// 健康检查
	router.GET("/api/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":       "ok",
			"version":      "1.0.0",
			"ipv6_enabled": true,
		})
	})

	// API v1
	v1 := router.Group("/api/v1")
	{
		v1.POST("/register", Register)
		v1.POST("/login", Login)
		v1.POST("/token/refresh", RefreshToken)
		v1.GET("/ice/servers", GetICEServers)

		// 密码重置接口 (无需认证)
		v1.POST("/password/reset/request", RequestPasswordReset)
		v1.POST("/password/reset/confirm", ConfirmPasswordReset)

		// 需要认证的路由
		auth := v1.Group("")
		auth.Use(JWTAuthMiddleware())
		{
			// 管理员接口
			admin := auth.Group("/admin")
			admin.Use(AdminOnly())
			{
				admin.POST("/reset-password", AdminResetPassword)
			}

			auth.POST("/device/status", ReportDeviceStatus)
		auth.GET("/devices", GetDevicesList)
		auth.GET("/_debug/routes", func(c *gin.Context) {
			c.JSON(200, gin.H{"routes": []string{"/device/status", "/devices"}})
		})

			auth.GET("/user/profile", GetUserProfile)
			auth.PUT("/user/profile", UpdateUserProfile)
			auth.DELETE("/user/account", DeleteAccount)
			auth.POST("/telemetry/ice", HandleICETelemetry)
			auth.POST("/logs/error", HandleErrorLog)
			auth.POST("/password/change", ChangePassword)
		}
	}

	// 启动服务
	port := getEnv("PORT", "8080")
	log.Printf("Starting API server on port %s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
