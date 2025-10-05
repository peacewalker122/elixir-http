defmodule MiniHttp.Env do
  @moduledoc """
  Lightweight loader for dotenv-style environment files.
  """

  @default_path ".env"

  @spec load(Path.t()) :: :ok
  def load(path \\ @default_path) do
    path
    |> Path.expand(File.cwd!())
    |> do_load()
  end

  defp do_load(path) do
    if File.exists?(path) do
      path
      |> File.stream!([], :line)
      |> Enum.each(&apply_line/1)
    end

    :ok
  end

  defp apply_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        :ok

      String.starts_with?(trimmed, "#") ->
        :ok

      String.starts_with?(trimmed, "export ") ->
        persist_pair(String.replace_prefix(trimmed, "export ", ""))

      true ->
        persist_pair(trimmed)
    end
  end

  defp persist_pair(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = strip_quotes(value)
        maybe_put_env(key, value)

      _ ->
        :ok
    end
  end

  defp strip_quotes(value) do
    trimmed = String.trim(value)

    cond do
      String.length(trimmed) >= 2 and String.starts_with?(trimmed, "\"") and
          String.ends_with?(trimmed, "\"") ->
        String.slice(trimmed, 1, String.length(trimmed) - 2)

      String.length(trimmed) >= 2 and String.starts_with?(trimmed, "'") and
          String.ends_with?(trimmed, "'") ->
        String.slice(trimmed, 1, String.length(trimmed) - 2)

      true ->
        trimmed
    end
  end

  defp maybe_put_env("", _value), do: :ok

  defp maybe_put_env(key, value) do
    case System.get_env(key) do
      nil -> System.put_env(key, value)
      _ -> :ok
    end
  end
end
