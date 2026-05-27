package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

type PlanRequest struct {
	Messages []PlanChatMessage `json:"messages"`
}

type PlanChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func sendSSE(w http.ResponseWriter, eventType string, data any) {
	payload, _ := json.Marshal(map[string]any{"type": eventType, "data": data})
	fmt.Fprintf(w, "data: %s\n\n", payload)
	w.(http.Flusher).Flush()
}

func planHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	if _, ok := w.(http.Flusher); !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	var req PlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendSSE(w, "error", map[string]string{"message": "invalid request body"})
		return
	}

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		sendSSE(w, "error", map[string]string{"message": "ANTHROPIC_API_KEY not configured"})
		return
	}

	client := anthropic.NewClient(option.WithAPIKey(apiKey))

	searchTool := anthropic.ToolParam{
		Name:        "search_places",
		Description: anthropic.String("Search for travel destinations, attractions, restaurants, or points of interest by name or description."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"query": map[string]any{
					"type":        "string",
					"description": "Search query, e.g. 'Eiffel Tower Paris' or 'best museums in Rome'",
				},
			},
			Required: []string{"query"},
		},
	}
	createTool := anthropic.ToolParam{
		Name:        "create_itinerary",
		Description: anthropic.String("Finalize the itinerary with the chosen list of locations to visit. Call this when you have identified all the places for the trip."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"locations": map[string]any{
					"type":        "array",
					"description": "Ordered list of locations to visit",
					"items": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"name":      map[string]any{"type": "string"},
							"place_id":  map[string]any{"type": "string"},
							"address":   map[string]any{"type": "string"},
							"latitude":  map[string]any{"type": "number"},
							"longitude": map[string]any{"type": "number"},
						},
						"required": []string{"name", "latitude", "longitude"},
					},
				},
				"summary": map[string]any{
					"type":        "string",
					"description": "A brief summary of the itinerary to show the user",
				},
			},
			Required: []string{"locations"},
		},
	}
	tools := []anthropic.ToolUnionParam{
		{OfTool: &searchTool},
		{OfTool: &createTool},
	}

	var messages []anthropic.MessageParam
	for _, m := range req.Messages {
		if m.Role == "user" {
			messages = append(messages, anthropic.NewUserMessage(anthropic.NewTextBlock(m.Content)))
		} else {
			messages = append(messages, anthropic.NewAssistantMessage(anthropic.NewTextBlock(m.Content)))
		}
	}

	systemPrompt := "You are an expert travel agent. Help users plan trips by searching for specific places and attractions. Use search_places to find real locations with coordinates. Search for individual places (e.g. 'Louvre Museum Paris') rather than broad queries. When you have gathered enough places for the user's trip, call create_itinerary to finalize the plan. Be conversational and helpful — ask clarifying questions if needed before searching."

	placesService := NewGooglePlacesService()
	ctx := r.Context()

	for {
		params := anthropic.MessageNewParams{
			Model:     anthropic.ModelClaudeSonnet4_6,
			MaxTokens: 4096,
			System: []anthropic.TextBlockParam{
				{
					Text:         systemPrompt,
					CacheControl: anthropic.NewCacheControlEphemeralParam(),
				},
			},
			Tools:    tools,
			Messages: messages,
		}

		stream := client.Messages.NewStreaming(ctx, params)
		resp := anthropic.Message{}

		for stream.Next() {
			event := stream.Current()
			resp.Accumulate(event)

			if ev, ok := event.AsAny().(anthropic.ContentBlockDeltaEvent); ok {
				if delta, ok := ev.Delta.AsAny().(anthropic.TextDelta); ok {
					sendSSE(w, "text_delta", map[string]string{"text": delta.Text})
				}
			}
		}
		if err := stream.Err(); err != nil {
			sendSSE(w, "error", map[string]string{"message": err.Error()})
			return
		}

		if resp.StopReason != anthropic.StopReasonToolUse {
			break
		}

		messages = append(messages, resp.ToParam())
		var toolResults []anthropic.ContentBlockParamUnion

		for _, block := range resp.Content {
			variant, ok := block.AsAny().(anthropic.ToolUseBlock)
			if !ok {
				continue
			}
			sendSSE(w, "tool_call", map[string]string{"name": variant.Name})

			switch variant.Name {
			case "search_places":
				var in struct {
					Query string `json:"query"`
				}
				json.Unmarshal(variant.Input, &in)

				results, err := placesService.SearchPlaces(in.Query)
				var resultStr string
				if err != nil {
					resultStr = fmt.Sprintf("Error searching places: %v", err)
				} else {
					b, _ := json.Marshal(results)
					resultStr = string(b)
				}
				sendSSE(w, "tool_result", map[string]string{"name": "search_places"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, resultStr, err != nil))

			case "create_itinerary":
				var in struct {
					Locations []map[string]any `json:"locations"`
					Summary   string           `json:"summary"`
				}
				json.Unmarshal(variant.Input, &in)
				sendSSE(w, "done", map[string]any{"locations": in.Locations, "summary": in.Summary})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Itinerary created successfully.", false))
			}
		}

		messages = append(messages, anthropic.NewUserMessage(toolResults...))

		select {
		case <-ctx.Done():
			return
		default:
		}
	}
}
