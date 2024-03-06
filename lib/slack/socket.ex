defmodule Slack.Socket do
  @moduledoc false
  # Slack websocket connection for "Socket Mode."
  use WebSockex

  require Logger

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  def start_link({app_token, bot_token, bot}) do
    state = %{
      app_token: app_token,
      bot_token: bot_token,
      bot: bot
    }

    {:ok, %{"url" => url}} = Slack.API.post("apps.connections.open", state.app_token)

    Logger.info("[Slack.Socket] connecting...")

    WebSockex.start_link(url, __MODULE__, state)
  end

  # ----------------------------------------------------------------------------
  # Callbacks
  # ----------------------------------------------------------------------------

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "hello"} = hello} ->
        Logger.info("[Slack.Socket] hello: #{inspect(hello)}")
        {:ok, state}

      {:ok, %{"payload" => %{"event" => event}} = msg} ->
        #Logger.debug("[Slack.Socket] message: #{inspect(msg)}")
        IO.inspect(Jason.encode!(event))
        Task.Supervisor.start_child(
          {:via, PartitionSupervisor, {Slack.TaskSupervisors, self()}},
          fn -> handle_slack_event(event["type"], event, state.bot) end
        )

        {:reply, ack_frame(msg), state}

      {:ok, %{"type" => "interactive", "payload" => %{"type" => event_type}} = msg} ->
        Logger.debug("[Slack.Socket] interactive action: #{inspect(msg)}")

        Task.Supervisor.start_child(
          {:via, PartitionSupervisor, {Slack.TaskSupervisors, self()}},
          fn -> handle_slack_event(event_type, msg["payload"], state.bot) end
        )

        {:reply, ack_frame(msg), state}
      _ ->
        Logger.debug("[Slack.Socket] Unhandled payload: #{msg}")
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_frame({type, msg}, state) do
    Logger.debug("[Slack.Socket] unhandled message type: #{inspect(type)}, msg: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:send, {type, msg} = frame}, state) do
    Logger.debug("[Slack.Socket] sending #{type} frame with payload: #{msg}")
    {:reply, frame, state}
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  # In the case the bot user has JOINED a channel, we need to handle this as a
  # special case.
  defp handle_slack_event(
         "member_joined_channel" = type,
         %{"user" => user} = event,
         %{user_id: user} = bot
       ) do
    Logger.debug("[Slack.Socket] member_joined_channel")
    handle_bot_joined(event, bot)
    bot.bot_module.handle_event(type, event)
  end

  # In the case the bot user has PARTED a channel, we need to handle this as a
  # special case.
  defp handle_slack_event("channel_left" = type, event, bot) do
    Logger.debug("[Slack.Socket] channel_left")
    handle_parted(event, bot)
    bot.bot_module.handle_event(type, event)
  end

  @allowed_event_ids ["jira_update", "github_update"]
  defp handle_slack_event(type, %{"text" => %{"event_id" => event_id}} = event, bot) do
    if event_id in @allowed_event_ids do
      Logger.debug("[Slack.Socket] Sending #{event_id} event to #{bot.bot_module}")
      bot.bot_module.handle_event(type, event)
    end
  end

  # Ignore messages from yourself...
  defp handle_slack_event("message", %{"user" => user}, %{user_id: user}), do: :ok
  defp handle_slack_event("message", %{"bot_id" => bot_id}, %{bot_id: bot_id}), do: :ok

  # Catch-all case, fall through to bot handler only.
  defp handle_slack_event(type, event, bot) do
    Logger.debug("[Slack.Socket] Sending #{type} event to #{bot.bot_module}")
    bot.bot_module.handle_event(type, event)
  end

  defp handle_bot_joined(%{"channel" => channel} = _event, bot) do
    Slack.ChannelServer.join(bot, channel)
  end

  defp handle_parted(%{"channel" => channel} = _event, bot) do
    Slack.ChannelServer.part(bot, channel)
  end

  defp ack_frame(payload) do
    ack =
      payload
      |> Map.take(["envelope_id"])
      |> Jason.encode!()

    {:text, ack}
  end
end
