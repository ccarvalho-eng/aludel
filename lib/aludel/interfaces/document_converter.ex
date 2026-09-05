defmodule Aludel.DocumentConverter do
  @moduledoc """
  Converts documents between formats for LLM consumption.

  Currently supports PDF to PNG conversion for the first page. The default
  adapter bounds the source and result sizes, conversion duration, diagnostic
  output, and ImageMagick resources.

  ## Usage

  PDF-to-image conversion is used for:
  - **OpenAI**: Chat API only supports images (PDFs work in Assistants API)
  - **Ollama**: Vision models require image formats

  Native PDF support:
  - **Anthropic Claude 4.5+**: Supports PDFs via document API

  ## Requirements

  Requires ImageMagick to be installed:
  - macOS: `brew install imagemagick`
  - Ubuntu/Debian: `apt-get install imagemagick`
  - Docker: Install in runtime image

  ## Configuration

  The conversion adapter can be configured in config files:

      config :aludel, :document_converter,
        adapter: Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick,
        density: 150,
        timeout_ms: 30_000,
        max_input_bytes: 10_485_760,
        max_output_bytes: 20_971_520,
        max_diagnostic_bytes: 16_384

  `density` accepts values from 72 through 300. Size and diagnostic limits can
  be lowered from their defaults, while `timeout_ms` accepts 100 through 60,000.
  An explicit `:executable` path and an existing `:temporary_directory` can also
  be supplied by trusted application configuration.

  For testing, use a stub adapter.
  """

  @type document :: %{data: binary(), content_type: String.t()}
  @type convert_result :: {:ok, document()} | {:error, term()}

  @default_adapter Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick

  @doc """
  Converts a PDF document to PNG format.

  Only converts the first page at 150 DPI for optimal text readability.
  Creates temporary files for conversion and cleans them up afterwards.

  ## Examples

      iex> pdf_doc = %{data: pdf_binary, content_type: "application/pdf"}
      iex> {:ok, png_doc} = DocumentConverter.pdf_to_image(pdf_doc)
      iex> png_doc.content_type
      "image/png"

      iex> image_doc = %{data: png_binary, content_type: "image/png"}
      iex> {:ok, ^image_doc} = DocumentConverter.pdf_to_image(image_doc)
      :ok
  """
  @spec pdf_to_image(document()) :: convert_result()
  def pdf_to_image(%{content_type: "application/pdf", data: pdf_data}) do
    {adapter, options} = adapter_config()

    case adapter.convert_pdf_to_png(pdf_data, options) do
      {:ok, png_data} ->
        {:ok, %{data: png_data, content_type: "image/png"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def pdf_to_image(doc) do
    {:ok, doc}
  end

  defp adapter_config do
    case Application.get_env(:aludel, :document_converter, []) do
      adapter when is_atom(adapter) and not is_nil(adapter) ->
        {adapter, []}

      config when is_list(config) ->
        {Keyword.get(config, :adapter, @default_adapter), Keyword.delete(config, :adapter)}

      _ ->
        {@default_adapter, []}
    end
  end
end
