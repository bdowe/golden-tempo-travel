package main

import (
	"fmt"
	"log"
	"net/smtp"
	"os"
	"strings"
)

// EmailService sends transactional mail over SMTP configured via env
// (SMTP_HOST/PORT/USERNAME/PASSWORD/FROM). Any SMTP provider works (Resend,
// Postmark, SES...) — swapping providers is an env change, no code. Missing
// config is degraded mode, same convention as a missing DUFFEL_ACCESS_TOKEN:
// the API stays healthy, sends are skipped with a log line that includes the
// would-be message so local dev can complete verify/reset flows from logs.
type EmailService struct {
	Host     string
	Port     string
	Username string
	Password string
	From     string
}

var emailService = NewEmailService()

func NewEmailService() *EmailService {
	s := &EmailService{
		Host:     os.Getenv("SMTP_HOST"),
		Port:     os.Getenv("SMTP_PORT"),
		Username: os.Getenv("SMTP_USERNAME"),
		Password: os.Getenv("SMTP_PASSWORD"),
		From:     os.Getenv("SMTP_FROM"),
	}
	if s.Port == "" {
		s.Port = "587"
	}
	if !s.Configured() {
		fmt.Println("Warning: SMTP_HOST/SMTP_FROM not set; email delivery disabled (verify/reset tokens will be logged instead)")
	}
	return s
}

func (s *EmailService) Configured() bool {
	return s.Host != "" && s.From != ""
}

// Send delivers a plain-text email. In degraded mode it logs the message
// (minus nothing — these are our own transactional bodies) and reports
// success so callers never surface delivery as a user-facing error.
func (s *EmailService) Send(to, subject, body string) error {
	if !s.Configured() {
		log.Printf("email (not sent, SMTP unconfigured) to=%s subject=%q body=%q", to, subject, body)
		return nil
	}
	msg := strings.Join([]string{
		"From: " + s.From,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=utf-8",
		"",
		body,
	}, "\r\n")

	var auth smtp.Auth
	if s.Username != "" {
		auth = smtp.PlainAuth("", s.Username, s.Password, s.Host)
	}
	return smtp.SendMail(s.Host+":"+s.Port, auth, s.From, []string{to}, []byte(msg))
}
