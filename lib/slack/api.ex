defmodule Slack.API do
  @moduledoc """
  Slack Web API.
  """

  require Logger

  @base_url "https://slack.com/api"

  @doc """
  Req client for Slack API.
  """
  @spec client(String.t()) :: Req.Request.t()
  def client(token) do
    Req.new(base_url: @base_url, auth: {:bearer, token})
  end

  @doc """
  GET from Slack API.
  """
  @spec get(String.t(), String.t(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def get(endpoint, token, args \\ %{}) do
    result =
      Req.get(client(token),
        url: endpoint,
        params: args
      )

    case result do
      {:ok, %{body: %{"ok" => true} = body}} ->
        {:ok, body}

      {_, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  @doc """
  POST to Slack API.
  """
  @spec post(String.t(), String.t(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def post(endpoint, token, args \\ %{}) do
      result = Req.post(client(token),
          url: endpoint,
          form: args
      )
      case result do
        {:ok, %{body: %{"ok" => true} = body}} ->
          {:ok, body}
        {:ok, %{body: %{"ok" => false} = body}} ->
          Logger.error(inspect(body))
          {:error, body}
        {:ok, %Req.Response{status: 200} = body} ->
          {:ok, body}
        {:error, error} ->
          Logger.error(inspect(error))
          {:error, error}
      end
  end

  @doc """
  GET pages from Slack API as a `Stream`.

  You can start at a cursor if you pass in `:next_cursor` as one of the `args`.
  Note that it is assumed to be an atom key. If you use a string key you'll
  end up with `next_cursor` parameter twice.
  """
  @spec stream(String.t(), String.t(), String.t(), map() | keyword()) :: Enumerable.t()
  def stream(endpoint, token, resource, args \\ %{}) do
    {starting_cursor, args} =
      args
      |> Map.new()
      |> Map.pop(:next_cursor, nil)
      |> IO.inspect(label: "Initial cursor and args")

    Stream.resource(
      # start_fun
      fn ->
        IO.inspect(starting_cursor, label: "Starting cursor")
        starting_cursor
      end,

      # next_fun
      fn
        "" ->
          IO.inspect("Empty cursor - halting", label: "Stream state")
          {:halt, nil}

        cursor ->
          IO.inspect(cursor, label: "Current cursor")
          merged_args = Map.merge(args, %{next_cursor: cursor})
          IO.inspect(merged_args, label: "Request args")
          case get(endpoint, token, merged_args) do
            {:ok, %{"ok" => true, ^resource => data} = body} ->
              next_cursor = get_in(body, ["response_metadata", "next_cursor"]) || ""
              IO.inspect(data, label: "Received data")
              IO.inspect(next_cursor, label: "Next cursor")
              {data, next_cursor}

            {_, error} ->
              IO.inspect(error, label: "Error in stream")
              raise "Error fetching #{resource}: #{inspect(error)}"
          end
      end,

      # end_fun
      fn acc ->
        IO.inspect(acc, label: "Stream ended with accumulator")
        acc
      end
    )
  end
end
