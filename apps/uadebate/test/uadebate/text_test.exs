defmodule Uadebate.TextTest do
  @moduledoc """
  Typed text: trimmed of whitespace and invisible characters, empty
  when nothing visible is left, no control characters, a length cap.
  """
  use ExUnit.Case, async: true

  alias Uadebate.Text

  test "nothing visible is empty" do
    for blank <- [nil, "", "   ", "\u00A0", " \u200B\u200C\u200D\uFEFF ", "\u2800\u3164", "\n\t"] do
      assert Text.clean(blank) == {:ok, nil}, inspect(blank)
      assert Text.clean(blank, required: true) == {:error, :required}, inspect(blank)
      assert Text.blank?(blank)
    end
  end

  test "trims the ends only" do
    assert Text.clean(" \u00A0Ann\u00A0Lee\u200B\uFEFF ") == {:ok, "Ann\u00A0Lee"}
    assert Text.clean("\u{1F469}\u200D\u{1F4BB}") == {:ok, "\u{1F469}\u200D\u{1F4BB}"}
    assert Text.trim("\u200B q \u00A0") == "q"
  end

  test "counts characters against max" do
    assert Text.clean(String.duplicate("\u0457", 5), max: 5) == {:ok, String.duplicate("\u0457", 5)}
    assert Text.clean(String.duplicate("x", 6), max: 5) == {:error, {:too_long, 5}}
  end

  test "refuses control characters; a long text keeps newlines and tabs" do
    for bad <- ["a\u0000b", "a\u0007b", "a\u007Fb", "a\u0085b", "a\nb", "a\tb", <<0xFF>>, ["a"]] do
      assert Text.clean(bad) == {:error, :invalid}, inspect(bad)
    end

    assert Text.clean("one\r\ntwo\tthree\rfour\n", multiline: true) ==
             {:ok, "one\ntwo\tthree\nfour"}

    assert Text.clean("a\u0000b", multiline: true) == {:error, :invalid}
  end
end
