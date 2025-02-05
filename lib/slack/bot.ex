defmodule Slack.Bot do
  @moduledoc """
  The Slack Bot.
  """

  @type t :: %__MODULE__{
          bot_id: String.t(),
          bot_module: module(),
          team_id: String.t(),
          user_id: String.t(),
          workspace_url: String.t()
        }

  @enforce_keys [:bot_id, :bot_module, :team_id, :user_id, :workspace_url]
  defstruct [:bot_id, :bot_module, :team_id, :user_id, :workspace_url]

  @doc """
  Handle the event from Slack.
  Return value is ignored.
  """
  @callback handle_event(type :: String.t(), payload :: map()) :: any()

  defmacro __using__(_opts) do
    quote do
      import Slack.Bot
      @behaviour Slack.Bot
    end
  end

  # Build a Bot struct from a string-keyed map.
  @doc false
  def from_string_params(bot_module, params) do
    %__MODULE__{
      bot_id: Map.fetch!(params, "bot_id"),
      bot_module: bot_module,
      team_id: Map.fetch!(params, "team_id"),
      user_id: Map.fetch!(params, "user_id"),
      workspace_url: Map.fetch!(params, "url"),
    }
  end

  @doc """
  Send a message to a channel.

  The `message` can be just the message text, or a `t:map/0` of properties that
  are accepted by Slack's `chat.postMessage` API endpoint.
  """
  @spec send_message(String.t(), String.t() | map()) :: Macro.t()
  defmacro send_message(channel, message) do
    quote do
      Slack.MessageServer.send(__MODULE__, unquote(channel), unquote(message))
    end
  end
end
