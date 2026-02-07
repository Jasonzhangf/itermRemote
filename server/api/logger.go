package main

import (
	"encoding/json"
	"math/rand"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// HandleErrorLog 处理错误日志上报
func HandleErrorLog(c *gin.Context) {
	claims := c.MustGet("claims").(*Claims)

	var log ErrorLog
	if err := c.ShouldBindJSON(&log); err != nil {
		c.JSON(400, gin.H{"error": "invalid payload"})
		return
	}

	log.UserID = claims.UserID

	// 脱敏
	sanitizeErrorLog(&log)

	// 采样
	if !shouldSample(&log) {
		c.JSON(200, gin.H{"status": "sampled"})
		return
	}

	// 异步存储
	go storeErrorLog(&log)

	c.JSON(200, gin.H{"status": "accepted"})
}

func sanitizeErrorLog(log *ErrorLog) {
	// 移除邮箱
	emailRegex := regexp.MustCompile(`\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b`)
	log.Error.Message = emailRegex.ReplaceAllString(log.Error.Message, "***@***.***")
	log.Error.StackTrace = emailRegex.ReplaceAllString(log.Error.StackTrace, "***@***.***")

	// 移除IPv4地址
	ipRegex := regexp.MustCompile(`\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b`)
	log.Error.Message = ipRegex.ReplaceAllString(log.Error.Message, "x.x.x.x")

	// 限制栈轨迹长度
	if len(log.Error.StackTrace) > 10000 {
		log.Error.StackTrace = log.Error.StackTrace[:10000] + "...[truncated]"
	}
}

func shouldSample(log *ErrorLog) bool {
	// 致命错误 100%
	if log.Severity == "fatal" {
		return true
	}

	// 错误 50%
	if log.Severity == "error" {
		return rand.Float64() < 0.5
	}

	// 警告 10%
	if log.Severity == "warning" {
		return rand.Float64() < 0.1
	}

	// 其他 1%
	return rand.Float64() < 0.01
}

func storeErrorLog(log *ErrorLog) {
	context, _ := json.Marshal(log.Context)

	record := map[string]interface{}{
		"id":              uuid.New(),
		"user_id":         log.UserID,
		"device_id":       log.DeviceID,
		"session_id":      log.SessionID,
		"trace_id":        log.TraceID,
		"span_id":         log.SpanID,
		"parent_span_id":  log.ParentSpanID,
		"error_code":      log.Error.Code,
		"error_message":   log.Error.Message,
		"stack_trace":     log.Error.StackTrace,
		"context":         context,
		"severity":        log.Severity,
		"sample_rate":     log.SampleRate,
	}

	db.Table("error_logs").Create(record)
}
