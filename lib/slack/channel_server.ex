defmodule Slack.ChannelServer do
  @moduledoc false
  use GenServer

  require Logger

  # By default the bot will join all conversations that it has access to.
  # For type options, see: [api](https://api.slack.com/methods/users.conversations).
  # Note, these require the following scopes:
  #   `channels:read`, `groups:read`, `im:read`, `mpim:read`
  @default_channel_types "public_channel,private_channel,mpim,im"
  @batch_size 100
  @batch_delay 200

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  def start_link({token, bot, config}) do
    Logger.info("[Slack.ChannelServer] starting for #{bot.bot_module}...")

    channel_types = case Keyword.get(config, :types) do
      nil -> @default_channel_types
      types when is_binary(types) -> types
      types when is_list(types) -> Enum.join(types, ",")
    end

    GenServer.start_link(__MODULE__, {token, bot, channel_types}, name: via_tuple(bot))
  end

  def join(bot, channel) do
    GenServer.cast(via_tuple(bot), {:join, channel})
  end

  def part(bot, channel) do
    GenServer.cast(via_tuple(bot), {:part, channel})
  end

  def get_bot(bot) do
    case Registry.lookup(Slack.ChannelServerRegistry, bot) do
      [{pid, _}] ->
        case GenServer.call(pid, :get_bot) do
          %Slack.Bot{} = bot -> {:ok, bot}
          other -> {:error, {:unexpected_response, other}}
        end
      [] ->
        {:error, :not_found}
    end
  end
  # ----------------------------------------------------------------------------
  # GenServer Callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init({token, bot, channel_types}) do
    state = %{
      bot: bot,
      channels: [],
      token: token,
      pending_channels: [],
      channel_types: channel_types
    }

    {:ok, state, {:continue, :fetch_channels}}
  end

  @impl true
  def handle_continue(:fetch_channels, state) do
    channels = fetch_channels(state.token, state.channel_types)
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
    end)

    Process.sleep(@batch_delay)

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


  @impl true
  def handle_call(:get_bot, _from, state) do
    {:reply, state.bot, state}
  end

  # ----------------------------------------------------------------------------
  # Private Functions
  # ----------------------------------------------------------------------------

  defp via_tuple(%Slack.Bot{bot_module: bot}) do
    {:via, Registry, {Slack.ChannelServerRegistry, bot}}
  end

  defp fetch_channels(token, types) when is_binary(types) do
    "users.conversations"
    |> Slack.API.stream(token, "channels", %{
      types: types,
      limit: 999
    })
    |> Stream.map(& &1["id"])
  end
end
