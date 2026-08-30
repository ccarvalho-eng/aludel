# Interfaces

Clean adapter patterns for external integrations, allowing dependency injection and easy testing.

## Structure

```
lib/aludel/interfaces/
├── llm.ex                          # LLM client (public API)
├── llm/                            # LLM adapters
│   ├── README.md                   # LLM-specific docs
│   ├── behaviour.ex                # Provider contract
│   ├── providers/
│   │   ├── openai.ex
│   │   ├── anthropic.ex
│   │   ├── google.ex
│   │   ├── ollama.ex
│   │   ├── xai.ex
│   │   ├── groq.ex
│   │   └── openrouter.ex
│   ├── adapters/http/
│   │   └── default.ex              # ReqLLM + telemetry
│   ├── config.ex
│   └── error_parser.ex
├── document_converter.ex           # Document converter (public API)
└── document_converter/             # Document conversion adapters
    ├── behaviour.ex                # Adapter contract
    └── adapters/
        └── imagemagick.ex          # ImageMagick PDF→PNG
```

## Design Principles

All interfaces follow these patterns:

1. **Behaviour-based**: Define contracts via `@behaviour`
2. **Dependency injection**: Configure adapters via Application config
3. **Runtime swappable**: Replace implementations for testing or different environments
4. **No type leakage**: Adapters never see library-specific types
5. **Testability**: Mock at adapter layer, not implementation

## Adding a New Interface

1. Create the public API module (e.g., `lib/aludel/interfaces/my_service.ex`)
2. Define the behaviour (e.g., `lib/aludel/interfaces/my_service/behaviour.ex`)
3. Implement adapters (e.g., `lib/aludel/interfaces/my_service/adapters/impl.ex`)
4. Configure default in public API module:
   ```elixir
   @default_adapter Aludel.Interfaces.MyService.Adapters.Impl

   defp adapter do
     Application.get_env(:aludel, :my_service, [])
     |> Keyword.get(:adapter, @default_adapter)
   end
   ```
5. Allow runtime override:
   ```elixir
   # config/config.exs
   config :aludel, :my_service,
     adapter: MyApp.CustomAdapter
   ```

## Examples

See subdirectories for specific interface documentation:
- [LLM Interfaces](llm/README.md) - Multi-provider LLM client
- Document Converter - PDF conversion for vision models
