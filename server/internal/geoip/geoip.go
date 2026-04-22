package geoip

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

type GeoResult struct {
	Country     string
	CountryCode string
	City        string
	ISP         string
}

type cacheEntry struct {
	result    GeoResult
	expiresAt time.Time
}

type Client struct {
	httpClient *http.Client
	cache      sync.Map
	ttl        time.Duration
}

func New() *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 5 * time.Second},
		ttl:        24 * time.Hour,
	}
}

func (c *Client) LookupIP(ctx context.Context, ip string) (GeoResult, error) {
	if ip == "" {
		return GeoResult{}, nil
	}
	if entry, ok := c.cache.Load(ip); ok {
		cached := entry.(cacheEntry)
		if time.Now().Before(cached.expiresAt) {
			return cached.result, nil
		}
		c.cache.Delete(ip)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://ip-api.com/json/%s?fields=status,country,countryCode,city,isp", ip), nil)
	if err != nil {
		log.Printf("geoip request build failed: %v", err)
		return GeoResult{}, nil
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		log.Printf("geoip lookup failed for %s: %v", ip, err)
		return GeoResult{}, nil
	}
	defer resp.Body.Close()
	var payload struct {
		Status      string `json:"status"`
		Country     string `json:"country"`
		CountryCode string `json:"countryCode"`
		City        string `json:"city"`
		ISP         string `json:"isp"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		log.Printf("geoip decode failed for %s: %v", ip, err)
		return GeoResult{}, nil
	}
	if payload.Status != "success" {
		return GeoResult{}, nil
	}
	result := GeoResult{Country: payload.Country, CountryCode: payload.CountryCode, City: payload.City, ISP: payload.ISP}
	c.cache.Store(ip, cacheEntry{result: result, expiresAt: time.Now().Add(c.ttl)})
	return result, nil
}
