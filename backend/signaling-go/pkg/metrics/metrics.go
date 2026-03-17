package metrics

import "github.com/prometheus/client_golang/prometheus"

var (
	WSConnections = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "bim_ws_connections",
		Help: "Current active websocket connections",
	})

	OnlineDevices = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "bim_online_devices",
		Help: "Current online devices",
	})

	ActiveSessions = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "bim_active_sessions",
		Help: "Current active sessions",
	})

	HTTPErrors = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "bim_http_errors_total",
		Help: "Total HTTP errors by route",
	}, []string{"route"})
)

func Register() {
	prometheus.MustRegister(WSConnections, OnlineDevices, ActiveSessions, HTTPErrors)
}
