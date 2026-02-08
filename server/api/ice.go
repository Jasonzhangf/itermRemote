package main

import (
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
)

type ICEServer struct {
    URLs []string `json:"urls"`
    Username string `json:"username,omitempty"`
    Credential string `json:"credential,omitempty"`
}

func GetICEServers(c *gin.Context) {
    servers := buildICEServers()
    c.JSON(http.StatusOK, gin.H{
        "ice_servers": servers,
        "selection": "client_rtt",
    })
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
            URLs: urls,
            Username: username,
            Credential: password,
        },
    }
}
