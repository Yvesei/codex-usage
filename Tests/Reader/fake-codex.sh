#!/bin/sh

state="start"

while IFS= read -r line; do
    case "$line" in
        *'"method":"initialize"'*)
            [ "$state" = "start" ] || exit 1
            state="initialized-response"
            printf '%s\n' '{"id":1,"result":{}}'
            ;;
        *'"method":"initialized"'*)
            [ "$state" = "initialized-response" ] || exit 1
            state="ready"
            ;;
        *account*rateLimits*read*)
            [ "$state" = "account-read" ] || exit 1
            case "$CODEX_USAGE_TEST_MODE" in
                network_error)
                    printf '%s\n' '{"id":3,"error":{"message":"network connection failed"}}'
                    ;;
                timeout_error)
                    printf '%s\n' '{"id":3,"error":{"message":"request timed out"}}'
                    ;;
                *)
                    printf '%s\n' '{"id":3,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}}}}'
                    ;;
            esac
            ;;
        *account*read*)
            [ "$state" = "ready" ] || exit 1
            state="account-read"
            case "$CODEX_USAGE_TEST_MODE" in
                no_account)
                    printf '%s\n' '{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}'
                    ;;
                api_key)
                    printf '%s\n' '{"id":2,"result":{"account":{"type":"apiKey"}}}'
                    ;;
                *)
                    printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"plus"}}}'
                    ;;
            esac
            ;;
    esac
done
