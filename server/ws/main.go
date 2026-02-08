package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

var (
	upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	clients  = make(map[string]*Client)
	clientsMux sync.RWMutex
	jwtSecret  = []byte(getEnv("JWT_SECRET", "secret"))
	redisClient *redis.Client
	ctx         = context.Background()
)

type Client struct {
	UserID   string
	DeviceID string
	Conn     *websocket.Conn
	Send     chan []byte
}

type Claims struct {
	UserID   string `json:"sub"`
	DeviceID string `json:"device_id"`
	jwt.RegisteredClaims
}

type PresenceDevice struct {
	UserID   string `json:"user_id"`
	DeviceID string `json:"device_id"`
}

type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

type ICEServersEvent struct {
	Type      string     `json:"type"`
	Timestamp int64      `json:"timestamp"`
	IceServers []ICEServer `json:"ice_servers"`
	Selection string     `json:"selection"`
}
type PresenceEvent struct {
	Type     string           `json:"type"`
	UserID   string           `json:"user_id,omitempty"`
	DeviceID string           `json:"device_id,omitempty"`
	Status   string           `json:"status,omitempty"`
	Timestamp int64           `json:"timestamp"`
	Online   []PresenceDevice `json:"online,omitempty"`
}

// ProxyEvent is a dynamic payload that the server only routes and does not parse.
// The payload is opaque to the server.
type ProxyEvent struct {
	Type           string          `json:"type"`
	Channel        string          `json:"channel"`
	SourceDeviceID string          `json:"source_device_id"`
	Target         string          `json:"target,omitempty"`
	Payload        json.RawMessage `json:"payload"`
	Timestamp      int64           `json:"timestamp"`
}

func main() {
	redisClient = redis.NewClient(&redis.Options{
		Addr:     getEnv("REDIS_HOST", "localhost:6379"),
		Password: getEnv("REDIS_PASSWORD", ""),
	})

	http.HandleFunc("/ws/health", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "ok", "clients": len(clients)})
	})
	http.HandleFunc("/ws/connect", handleWebSocket)

	port := getEnv("PORT", "8081")
	log.Printf("WS server on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	claims, err := validateToken(token)
	if err != nil {
		http.Error(w, "unauthorized", 401)
		return
	}

	conn, _ := upgrader.Upgrade(w, r, nil)
	client := &Client{UserID: claims.UserID, DeviceID: claims.DeviceID, Conn: conn, Send: make(chan []byte, 256)}

	key := clientKey(client.UserID, client.DeviceID)

	clientsMux.Lock()
	clients[key] = client
	clientsMux.Unlock()

	redisClient.Set(ctx, redisOnlineKey(client.UserID, client.DeviceID), "true", 90*time.Second)

	// Send current online list to the newly connected client
	client.Send <- mustJSON(PresenceEvent{
		Type:      "presence_sync",
		Timestamp: time.Now().Unix(),
		Online:    listOnlineDevices(),
	})

	client.Send <- mustJSON(ICEServersEvent{
		Type:       "ice_servers",
		Timestamp:  time.Now().Unix(),
		IceServers: buildICEServers(),
		Selection:  "client_rtt",
	})

	broadcastPresence("online", client)

	go client.writePump()
	go client.readPump(client)
}

func (c *Client) readPump(client *Client) {
	defer c.cleanup()
	c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		redisClient.Set(ctx, redisOnlineKey(c.UserID, c.DeviceID), "true", 90*time.Second)
		return nil
	})

	for {
		_, raw, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		client.handleDynamicMessage(raw)
	}
}

func (c *Client) handleDynamicMessage(raw []byte) {
	var event ProxyEvent
	if err := json.Unmarshal(raw, &event); err != nil {
		return
	}
	if event.Type != "proxy" || event.Channel == "" {
		return
	}

	event.SourceDeviceID = c.DeviceID
	if event.Timestamp == 0 {
		event.Timestamp = time.Now().Unix()
	}

	payload := mustJSON(event)

	clientsMux.RLock()
	defer clientsMux.RUnlock()
	for _, target := range clients {
		if target.UserID != c.UserID {
			continue
		}
		if event.Target == "" || event.Target == "broadcast" || event.Target == target.DeviceID {
			select {
			case target.Send <- payload:
			default:
			}
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case msg := <-c.Send:
			c.Conn.WriteMessage(websocket.TextMessage, msg)
		case <-ticker.C:
			c.Conn.WriteMessage(websocket.PingMessage, nil)
		}
	}
}

func (c *Client) cleanup() {
	key := clientKey(c.UserID, c.DeviceID)

	clientsMux.Lock()
	delete(clients, key)
	clientsMux.Unlock()

	redisClient.Del(ctx, redisOnlineKey(c.UserID, c.DeviceID))

	broadcastPresence("offline", c)
}

func validateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}
	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	return nil, jwt.ErrSignatureInvalid
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func clientKey(userID, deviceID string) string {
	return userID + ":" + deviceID
}

func redisOnlineKey(userID, deviceID string) string {
	return "online:" + userID + ":" + deviceID
}

func listOnlineDevices() []PresenceDevice {
	clientsMux.RLock()
	defer clientsMux.RUnlock()
	devices := make([]PresenceDevice, 0, len(clients))
	for _, c := range clients {
		devices = append(devices, PresenceDevice{UserID: c.UserID, DeviceID: c.DeviceID})
	}
	return devices
}

func broadcastPresence(status string, client *Client) {
	event := PresenceEvent{
		Type:      "presence_update",
		UserID:    client.UserID,
		DeviceID:  client.DeviceID,
		Status:    status,
		Timestamp: time.Now().Unix(),
	}
	payload := mustJSON(event)

	clientsMux.RLock()
	defer clientsMux.RUnlock()
	for _, c := range clients {
		select {
		case c.Send <- payload:
		default:
		}
	}
}

func mustJSON(v interface{}) []byte {
	data, _ := json.Marshal(v)
	return data
}

func buildICEServers() []ICEServer {
	raw := getEnv("TURN_SERVERS", "code.codewhisper.cc:3478,coder1.codewhisper.cc:3478")
	username := getEnv("TURN_USERNAME", "itermremote")
	password := getEnv("TURN_PASSWORD", "turnpass123!")
	if raw == "" {
		return []ICEServer{}
	}
	hosts := strings.Split(raw, ",")
	urls := make([]string, 0, len(hosts)*2)
	for _, host := range hosts {
		host = strings.TrimSpace(host)
		if host == "" {
			continue
		}
		urls = append(urls, "turn:"+host+"?transport=udp")
		urls = append(urls, "turn:"+host+"?transport=tcp")
	}

	return []ICEServer{
		{
			URLs:       urls,
			Username:   username,
			Credential: password,
		},
	}
}
