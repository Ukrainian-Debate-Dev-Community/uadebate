defmodule Uadebate.Text do
  @moduledoc """
  Typed text, cleaned one way in every form (the same rules as cab's
  Core.Text). `clean/2` trims whitespace and invisible characters at
  both ends (Unicode spaces, no-break spaces included, zero-width
  spaces and joiners, the byte-order mark, bidi marks, Hangul fillers,
  the braille blank): text with nothing visible left is empty, `nil`.
  It refuses control characters (a long text keeps newlines and tabs,
  its line breaks made LF) and anything that is not UTF-8 text, and
  counts the length in characters. Error codes:

    * `:required` - empty, while `required: true`
    * `{:too_long, max}` - more than `max:` characters
    * `:invalid` - a control character, or not text at all

  `clean_text/3` does the same on a changeset, with the messages in
  the errors domain.
  """

  use Gettext, backend: UadebateWeb.Gettext

  import Ecto.Changeset

  @doc """
  The cleaned text: `{:ok, text}`, `{:ok, nil}` for empty text, or
  `{:error, code}`. Options: `required:` (empty is an error), `max:`
  (characters), `multiline:` (newlines and tabs allowed).
  """
  def clean(value, opts \\ [])

  def clean(nil, opts), do: empty(opts)

  def clean(value, opts) when is_binary(value) do
    multiline = Keyword.get(opts, :multiline, false)
    max = opts[:max]

    if String.valid?(value) do
      text = value |> line_breaks(multiline) |> trim()

      cond do
        text == "" -> empty(opts)
        control?(text, multiline) -> {:error, :invalid}
        max && String.length(text) > max -> {:error, {:too_long, max}}
        true -> {:ok, text}
      end
    else
      {:error, :invalid}
    end
  end

  def clean(_value, _opts), do: {:error, :invalid}

  @doc """
  The text without whitespace and invisible characters at its ends,
  `""` when nothing visible is left (or for anything but UTF-8 text).
  """
  def trim(value) when is_binary(value) do
    if String.valid?(value),
      do:
        String.replace(
          value,
          ~r/\A[\s\p{Z}\p{Cf}\x{034F}\x{115F}\x{1160}\x{2800}\x{3164}\x{FFA0}]+|[\s\p{Z}\p{Cf}\x{034F}\x{115F}\x{1160}\x{2800}\x{3164}\x{FFA0}]+\z/u,
          ""
        ),
      else: ""
  end

  def trim(_value), do: ""

  @doc "Is nothing visible typed?"
  def blank?(value), do: trim(value) == ""

  @doc """
  Cleans the changed `fields` of a changeset with `clean/2`: the
  cleaned text, or nil when nothing visible is left (`blank:` puts
  that value instead). Takes `clean/2`'s options; `required: true`
  refuses empty text.
  """
  def clean_text(changeset, fields, opts \\ []) do
    Enum.reduce(List.wrap(fields), changeset, fn field, acc ->
      acc
      |> clean_field(field, opts)
      |> then(&if(opts[:required], do: require_field(&1, field), else: &1))
    end)
  end

  defp clean_field(changeset, field, opts) do
    case fetch_change(changeset, field) do
      {:ok, value} when is_binary(value) ->
        case clean(value, Keyword.take(opts, [:max, :multiline])) do
          {:ok, nil} -> put_change(changeset, field, Keyword.get(opts, :blank))
          {:ok, text} -> put_change(changeset, field, text)
          {:error, code} -> add_error(changeset, field, message(code), error_opts(code))
        end

      # cast already made a blank (spaces only) value nil
      {:ok, nil} ->
        if Keyword.has_key?(opts, :blank),
          do: put_change(changeset, field, opts[:blank]),
          else: changeset

      _ ->
        changeset
    end
  end

  defp require_field(changeset, field) do
    if changeset.errors[field],
      do: changeset,
      else: validate_required(changeset, field, message: message(:required))
  end

  defp error_opts({:too_long, max}),
    do: [count: max, validation: :length, kind: :max, type: :string]

  defp error_opts(:invalid), do: [validation: :format]

  @doc "An error code as a message."
  def message(:required), do: dgettext("errors", "Fill this in.")

  def message({:too_long, max}),
    do: dgettext("errors", "%{count} characters at most.", count: max)

  def message(:invalid), do: dgettext("errors", "Use plain text without control characters.")

  defp empty(opts) do
    if opts[:required], do: {:error, :required}, else: {:ok, nil}
  end

  defp line_breaks(text, true), do: String.replace(text, ~r/\r\n?/, "\n")
  defp line_breaks(text, false), do: text

  defp control?(text, true), do: text =~ ~r/[^\P{Cc}\n\t]/u
  defp control?(text, false), do: text =~ ~r/\p{Cc}/u
end
