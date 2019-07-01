package main

import (
	"github.com/prometheus/client_golang/prometheus"
)

// Define Prometheus Exporter namespace (prefix) for all metric names
const metricNamespace string = "sealed_secrets_controller"

// Define Prometheus metrics to expose
var (
	unsealCountTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: metricNamespace,
			Name:      "unseal_count_total",
			Help:      "Total number of sealed secret unseal attempts by action and status",
		},
		// We will want to monitor the worker ID that processed the
		// job, and the type of job that was processed
		[]string{"action", "status"},
	)
)

func init() {
	// Register metrics with Prometheus
	prometheus.MustRegister(unsealCountTotal)
}
