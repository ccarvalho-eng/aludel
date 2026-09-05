defmodule Aludel.Interfaces.DocumentConverter.Behaviour do
  @moduledoc """
  Behaviour for document conversion adapters.

  Allows swapping between different conversion tools (ImageMagick, etc.)
  or using test stubs.
  """

  @type document :: %{data: binary(), content_type: String.t()}
  @type convert_result :: {:ok, binary()} | {:error, term()}

  @doc """
  Converts a PDF to PNG format using adapter-specific options.

  Returns the PNG binary data on success.
  """
  @callback convert_pdf_to_png(pdf_data :: binary(), opts :: keyword()) ::
              convert_result()
end
