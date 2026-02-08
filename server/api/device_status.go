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

    key := "device:ips:" + req.DeviceID
    redisClient.HSet(ctx, key, map[string]interface{}{
        "ipv4_lan":    joinList(req.IPv4LAN),
        "ipv4_ts":     joinList(req.IPv4TS),
        "ipv6_public": joinList(req.IPv6Public),
        "updated_at":  time.Now().Unix(),
        "is_online":   isOnline,
    })
    redisClient.Expire(ctx, key, 10*time.Minute)

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

// GetDevicesList 获取设备列表及可连接 IP
func GetDevicesList(c *gin.Context) {
    userID := c.GetString("user_id")
    if userID == "" {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
        return
    }

    var devices []Device
    if err := db.Where("user_id = ?", userID).Find(&devices).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query devices"})
        return
    }

    var result []DeviceStatusResponse
    for _, d := range devices {
        key := "device:ips:" + d.DeviceID
        data, _ := redisClient.HGetAll(ctx, key).Result()

        result = append(result, DeviceStatusResponse{
            DeviceID:   d.DeviceID,
            UserID:     userID,
            DeviceName: d.DeviceName,
            DeviceType: d.DeviceType,
            IPv4LAN:    parseList(data["ipv4_lan"]),
            IPv4TS:     parseList(data["ipv4_ts"]),
            IPv6Public: parseList(data["ipv6_public"]),
            IsOnline:   parseBool(data["is_online"], d.IsOnline),
            UpdatedAt:  parseInt(data["updated_at"]),
        })
    }

    c.JSON(http.StatusOK, gin.H{"devices": result})
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
