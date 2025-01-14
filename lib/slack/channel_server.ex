defmodule Slack.ChannelServer do
  @moduledoc false
  use GenServer

  require Logger

  # By default the bot will join all conversations that it has access to.
  # For type options, see: [api](https://api.slack.com/methods/users.conversations).
  # Note, these require the following scopes:
  #   `channels:read`, `groups:read`, `im:read`, `mpim:read`
  @default_channel_types "public_channel,private_channel,mpim,im"
  @batch_size 10
  @batch_delay 200

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  def start_link({token, bot, config}) do
    Logger.info("[Slack.ChannelServer] starting for #{bot.bot_module}...")

    # This should be either channel types or channel IDs
    channels_or_types = case Keyword.get(config, :types) do
      nil -> @default_channel_types
      types when is_binary(types) -> types
      types when is_list(types) -> types  # Keep as list if it's channel IDs
    end

    GenServer.start_link(__MODULE__, {token, bot, channels_or_types}, name: via_tuple(bot))
  end

  def join(bot, channel) do
    GenServer.cast(via_tuple(bot), {:join, channel})
  end

  def part(bot, channel) do
    GenServer.cast(via_tuple(bot), {:part, channel})
  end

  # ----------------------------------------------------------------------------
  # GenServer Callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init({token, bot, channels_or_types}) do
    state = %{
      bot: bot,
      channels: [],
      token: token,
      pending_channels: [],
      channels_or_types: channels_or_types
    }

    {:ok, state, {:continue, :fetch_channels}}
  end

  @impl true
  def handle_continue(:fetch_channels, state) do
    channels = case state.channels_or_types do
      types when is_binary(types) ->
        # Fetch channels from Slack API if types are provided
        fetch_channels_from_api(state.token, types)
      channel_ids when is_list(channel_ids) ->
        # Use provided channel IDs directly
        channel_ids
    end

    {:noreply, %{state | pending_channels: channels}, {:continue, :process_channels}}
  end

  @impl true
  def handle_continue(:process_channels, %{pending_channels: []} = state) do
    Logger.info("[Slack.ChannelServer] Finished processing all channels")
    {:noreply, state}
  end

  @impl true
  def handle_continue(:process_channels, %{pending_channels: pending} = state) do
    {batch, remaining} = Enum.split(pending, @batch_size)

    # Process each channel in the batch with delay
    Enum.each(batch, fn channel ->
      Logger.info("[Slack.ChannelServer] #{state.bot.bot_module} joining #{channel}...")
      {:ok, _} = Slack.MessageServer.start_supervised(state.token, state.bot, channel)
      Process.sleep(@batch_delay)
    end)

    new_state = %{state |
      channels: state.channels ++ batch,
      pending_channels: remaining
    }

    if remaining == [] do
      {:noreply, new_state}
    else
      {:noreply, new_state, {:continue, :process_channels}}
    end
  end

  @impl true
  def handle_cast({:join, channel}, state) do
    Logger.info("[Slack.ChannelServer] #{state.bot.bot_module} joining #{channel}...")
    {:ok, _} = Slack.MessageServer.start_supervised(state.token, state.bot, channel)
    {:noreply, %{state | channels: [channel | state.channels]}}
  end

  @impl true
  def handle_cast({:part, channel}, state) do
    Logger.info("[Slack.ChannelServer] #{state.bot.bot_module} leaving #{channel}...")
    :ok = Slack.MessageServer.stop(state.bot, channel)
    {:noreply, %{state | channels: List.delete(state.channels, channel)}}
  end

  # ----------------------------------------------------------------------------
  # Private Functions
  # ----------------------------------------------------------------------------

  defp via_tuple(%Slack.Bot{bot_module: bot}) do
    {:via, Registry, {Slack.ChannelServerRegistry, bot}}
  end

  defp fetch_channels_from_api(token, types) when is_binary(types) do
    "users.conversations"
    |> Slack.API.stream(token, "channels", %{
      types: types,
      limit: 100  # Reduced batch size for API calls
    })
    |> Stream.map(& &1["id"])
  end
end
