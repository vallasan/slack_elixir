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
    if endpoint == "chat.postMessage" do
      result =
      Req.post(client(token),
        url: endpoint,
        form: args
        #body: Jason.encode!(args)
      )
    else
      result =
      Req.post(client(token),
        url: endpoint,
        #form: args
        body: Jason.encode!(args)
      )
    end
    case result do
      {:ok, %{body: %{"ok" => true} = body}} ->
        {:ok, body}

      {_, error} ->
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

    Stream.resource(
      # start_fun
      fn -> starting_cursor end,

      # next_fun
      fn
        "" ->
          {:halt, nil}

        cursor ->
          case get(endpoint, token, Map.merge(args, %{next_cursor: cursor})) do
            {:ok, %{"ok" => true, ^resource => data} = body} ->
              cursor = get_in(body, ["response_metadata", "next_cursor"]) || ""
              {data, cursor}

            {_, error} ->
              raise "Error fetching #{resource}: #{inspect(error)}"
          end
      end,

      # end_fun
      fn acc ->
        acc
      end
    )
  end
end
