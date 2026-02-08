package main

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type PasswordResetRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type PasswordResetConfirmRequest struct {
	Token       string `json:"token" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8"`
}

type AdminResetPasswordRequest struct {
	UserID      string `json:"user_id" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8"`
}

func AdminOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		claims := c.MustGet("claims").(*Claims)
		var user User
		if err := db.First(&user, "id = ?", claims.UserID).Error; err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			return
		}
		if user.Role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin required"})
			return
		}
		c.Next()
	}
}

func RequestPasswordReset(c *gin.Context) {
	var req PasswordResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user User
	if err := db.Where("email = ?", req.Email).First(&user).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	token := generateResetToken()
	expiresAt := time.Now().Add(30 * time.Minute)
	resetToken := PasswordResetToken{
		UserID:    user.ID,
		Token:     token,
		ExpiresAt: expiresAt,
	}

	if err := db.Create(&resetToken).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create reset token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":     "ok",
		"reset_token": token,
		"expires_at":  expiresAt,
	})
}

func ConfirmPasswordReset(c *gin.Context) {
	var req PasswordResetConfirmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var token PasswordResetToken
	if err := db.Where("token = ? AND used_at IS NULL AND expires_at > ?", req.Token, time.Now()).First(&token).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	newHash := hashPassword(req.NewPassword)
	if err := db.Model(&User{}).Where("id = ?", token.UserID).Update("password_hash", newHash).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update password"})
		return
	}

	now := time.Now()
	if err := db.Model(&token).Update("used_at", &now).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mark token used"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func AdminResetPassword(c *gin.Context) {
	var req AdminResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	newHash := hashPassword(req.NewPassword)
	if err := db.Model(&User{}).Where("id = ?", req.UserID).Update("password_hash", newHash).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reset password"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func generateResetToken() string {
	buf := make([]byte, 32)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}

