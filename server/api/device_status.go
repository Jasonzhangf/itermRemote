package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type DeviceStatusRequest struct {
	DeviceID   string   `json:"device_id"`
	DeviceName string   `json:"device_name"`
	DeviceType string   `json:"device_type"`
	IPv4LAN    []string `json:"ipv4_lan"`
	IPv4TS     []string `json:"ipv4_tailscale"`
	IPv6Public []string `json:"ipv6_public"`
	IsOnline   *bool    `json:"is_online"`
}

type DeviceStatusResponse struct {
	DeviceID   string   `json:"device_id"`
	UserID     string   `json:"user_id"`
	DeviceName string   `json:"device_name"`
	DeviceType string   `json:"device_type"`
	IPv4LAN    []string `json:"ipv4_lan"`
	IPv4TS     []string `json:"ipv4_tailscale"`
	IPv6Public []string `json:"ipv6_public"`
	IsOnline   bool     `json:"is_online"`
	UpdatedAt  int64    `json:"updated_at"`
}

// ReportDeviceStatus 设备上报自己的可连接 IP 列表
func ReportDeviceStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req DeviceStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.DeviceID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "device_id required"})
		return
	}

	isOnline := true
	if req.IsOnline != nil {
		isOnline = *req.IsOnline
	}

	var device Device
	err := db.Where("user_id = ? AND device_id = ?", userID, req.DeviceID).First(&device).Error
	if err != nil {
		device = Device{
			ID:         uuid.New(),
			UserID:     uuid.MustParse(userID),
			DeviceID:   req.DeviceID,
			DeviceName: req.DeviceName,
			DeviceType: req.DeviceType,
			IsOnline:   isOnline,
			LastSeenAt: ptrTime(time.Now()),
		}
		db.Create(&device)
	} else {
		device.DeviceName = req.DeviceName
		device.DeviceType = req.DeviceType
		device.IsOnline = isOnline
		device.LastSeenAt = ptrTime(time.Now())
		db.Save(&device)
	}

	key := "device:ips:" + userID + ":" + req.DeviceID
	redisClient.HSet(ctx, key, map[string]interface{}{
		"ipv4_lan":    joinList(req.IPv4LAN),
		"ipv4_ts":     joinList(req.IPv4TS),
		"ipv6_public": joinList(req.IPv6Public),
		"updated_at":  time.Now().Unix(),
		"is_online":   isOnline,
		"device_name": req.DeviceName,
		"device_type": req.DeviceType,
	})
	// 10秒心跳，允许3次心跳丢失 => 30秒TTL
	ttl := getEnvInt("DEVICE_TTL_SECONDS", 30)
	redisClient.Expire(ctx, key, time.Duration(ttl)*time.Second)

	c.JSON(http.StatusOK, DeviceStatusResponse{
		DeviceID:   req.DeviceID,
		UserID:     userID,
		DeviceName: req.DeviceName,
		DeviceType: req.DeviceType,
		IPv4LAN:    req.IPv4LAN,
		IPv4TS:     req.IPv4TS,
		IPv6Public: req.IPv6Public,
		IsOnline:   isOnline,
		UpdatedAt:  time.Now().Unix(),
	})
}

// GetDevicesList 获取设备列表及可连接 IP（只返回5分钟内有心跳的在线设备）
func GetDevicesList(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// 从Redis获取该用户的所有设备
	pattern := "device:ips:" + userID + ":*"
	var cursor uint64
	var keys []string
	
	for {
		var batch []string
		var err error
		batch, cursor, err = redisClient.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			break
		}
		keys = append(keys, batch...)
		if cursor == 0 {
			break
		}
	}

	// Deduplicate by device_id - keep most recent
	deviceMap := make(map[string]DeviceStatusResponse)
	
	ttl := getEnvInt("DEVICE_TTL_SECONDS", 30)
	cutoff := time.Now().Add(-time.Duration(ttl) * time.Second).Unix()

	for _, key := range keys {
		data, err := redisClient.HGetAll(ctx, key).Result()
		if err != nil || len(data) == 0 {
			continue
		}

		updatedAt := parseInt(data["updated_at"])
		// 只返回5分钟内有更新的设备
		if updatedAt < cutoff {
			continue
		}

		// 从key中提取device_id
		deviceID := ""
		parts := splitKey(key)
		if len(parts) >= 2 {
			deviceID = parts[len(parts)-1]
		}

		// Skip if we already have a newer entry for this device
		if existing, ok := deviceMap[deviceID]; ok && existing.UpdatedAt >= updatedAt {
			continue
		}

		deviceMap[deviceID] = DeviceStatusResponse{
			DeviceID:   deviceID,
			UserID:     userID,
			DeviceName: data["device_name"],
			DeviceType: data["device_type"],
			IPv4LAN:    parseList(data["ipv4_lan"]),
			IPv4TS:     parseList(data["ipv4_ts"]),
			IPv6Public: parseList(data["ipv6_public"]),
			IsOnline:   parseBool(data["is_online"], true),
			UpdatedAt:  updatedAt,
		}
	}

	// Convert map to slice
	var result []DeviceStatusResponse
	for _, dev := range deviceMap {
		result = append(result, dev)
	}

	c.JSON(http.StatusOK, gin.H{"devices": result})
}

func splitKey(key string) []string {
	var parts []string
	current := ""
	for _, ch := range key {
		if ch == ':' {
			if current != "" {
				parts = append(parts, current)
				current = ""
			}
		} else {
			current += string(ch)
		}
	}
	if current != "" {
		parts = append(parts, current)
	}
	return parts
}

func ptrTime(t time.Time) *time.Time { return &t }

func parseList(v string) []string {
	if v == "" {
		return []string{}
	}
	var out []string
	for _, part := range splitCSV(v) {
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func splitCSV(v string) []string {
	res := []string{}
	current := ""
	for _, ch := range v {
		if ch == ',' || ch == ' ' {
			if current != "" {
				res = append(res, current)
				current = ""
			}
		} else {
			current += string(ch)
		}
	}
	if current != "" {
		res = append(res, current)
	}
	return res
}

func joinList(v []string) string {
	if len(v) == 0 {
		return ""
	}
	out := ""
	for i, s := range v {
		if s == "" {
			continue
		}
		if i > 0 {
			out += ","
		}
		out += s
	}
	return out
}

func parseInt(v string) int64 {
	if v == "" {
		return 0
	}
	t, _ := strconv.ParseInt(v, 10, 64)
	return t
}

func parseBool(v string, fallback bool) bool {
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}
