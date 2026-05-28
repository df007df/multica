package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		fmt.Printf("connect error: %v\n", err)
		return
	}
	defer conn.Close(ctx)

	// Find issues with invalid priority
	fmt.Println("--- issues with invalid priority ---")
	rows, err := conn.Query(ctx, `
		SELECT id, title, priority
		FROM issue
		WHERE priority NOT IN ('urgent', 'high', 'medium', 'low', 'none')
		   OR priority IS NULL
	`)
	if err != nil {
		fmt.Printf("query error: %v\n", err)
		return
	}
	defer rows.Close()

	found := false
	for rows.Next() {
		var id, title string
		var priority interface{}
		rows.Scan(&id, &title, &priority)
		fmt.Printf("  id=%s title=%q priority=%v\n", id, title, priority)
		found = true
	}
	if !found {
		fmt.Println("  none found")
	}

	// All distinct values (including null)
	fmt.Println("\n--- distinct issue priority (including null) ---")
	rows2, _ := conn.Query(ctx, "SELECT DISTINCT priority FROM issue ORDER BY 1")
	for rows2.Next() {
		var s interface{}
		rows2.Scan(&s)
		fmt.Printf("  %v\n", s)
	}

	// Count nulls
	var nullCount int
	conn.QueryRow(ctx, "SELECT count(*) FROM issue WHERE priority IS NULL").Scan(&nullCount)
	fmt.Printf("\nnull priority count: %d\n", nullCount)
}
