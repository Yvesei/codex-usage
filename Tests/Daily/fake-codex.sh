#!/bin/sh

state=start

while IFS= read -r line; do
    case "$line" in
        *'"initialize"'*)
            [ "$state" = start ] || exit 1
            state=initialized
            printf '%s\n' '{"id":1,"result":{}}'
            ;;
        *'"initialized"'*)
            [ "$state" = initialized ] || exit 1
            state=ready
            ;;
        *'account/usage/read'*|*'account\/usage\/read'*)
            [ "$state" = account ] || exit 1
            case "$DAILY_TOKEN_TEST_MODE" in
                unsupported)
                    printf '%s\n' '{"id":3,"error":{"code":-32601,"message":"Method not found"}}'
                    ;;
                null)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":null}}'
                    ;;
                empty)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":[]}}'
                    ;;
                invalid_date)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2026-02-29","tokens":10}]}}'
                    ;;
                negative)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2026-02-28","tokens":-1}]}}'
                    ;;
                boolean)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2026-02-28","tokens":true}]}}'
                    ;;
                network_error)
                    printf '%s\n' '{"id":3,"error":{"message":"network connection failed"}}'
                    ;;
                *)
                    printf '%s\n' '{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2024-02-29","tokens":9007199254740993},{"startDate":"2024-03-01","tokens":0}]}}'
                    ;;
            esac
            ;;
        *'account/read'*|*'account\/read'*)
            [ "$state" = ready ] || exit 1
            state=account
            case "$DAILY_TOKEN_TEST_MODE" in
                no_account)
                    printf '%s\n' '{"id":2,"result":{"account":null}}'
                    ;;
                api_key)
                    printf '%s\n' '{"id":2,"result":{"account":{"type":"apiKey"}}}'
                    ;;
                *)
                    printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"test@example.com"}}}'
                    ;;
            esac
            ;;
    esac
done
