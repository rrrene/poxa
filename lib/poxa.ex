defmodule Poxa do
  @moduledoc """
  This application is a server that understands the Pusher Protocol
  More info at: http://pusher.com/docs/pusher_protocol
  """
  use Application
  require Logger

  @registry_adapter Poxa.Registry.adapter

  def registry, do: @registry_adapter

  def start(_type, _args) do
    dispatch = :cowboy_router.compile([
      {:_, [ { '/ping', Poxa.PingHandler, [] },
             { '/console', Poxa.Console.WSHandler, [] },
             { '/', :cowboy_static, {:priv_file, :poxa, 'index.html'} },
             { '/static/[...]', :cowboy_static, {:priv_dir, :poxa, 'static'} },
             { '/apps/:app_id/events', Poxa.EventHandler, [] },
             { '/apps/:app_id/channels[/:channel_name]', Poxa.ChannelsHandler, [] },
             { '/apps/:app_id/channels/:channel_name/users', Poxa.UsersHandler, [] },
             { '/app/:app_key', Poxa.WebsocketHandler, [] } ] }
    ])
    case load_config do
      {:ok, config} ->
        Logger.info "Starting Poxa using app_key: #{config.app_key}, app_id: #{config.app_id}, app_secret: #{config.app_secret} on port #{config.port}"
        {:ok, _} = :cowboy.start_http(:poxa, 100,
                                      [port: config.port],
                                      [env: [dispatch: dispatch]])
        run_ssl(dispatch)
        Poxa.Supervisor.start_link
      :invalid_configuration ->
        Logger.error "Error on start, set app_key, app_id and app_secret"
        exit(:invalid_configuration)
    end

  end

  def stop(_State) do
    :ok = :cowboy.stop_listener(:poxa)
  end

  defp load_config do
    try do
      {:ok, app_key} = Application.fetch_env(:poxa, :app_key)
      {:ok, app_id} = Application.fetch_env(:poxa, :app_id)
      {:ok, app_secret} = Application.fetch_env(:poxa, :app_secret)
      {:ok, port} = Application.fetch_env(:poxa, :port)
      {:ok, registry_adapter} = Application.fetch_env(:poxa, :registry_adapter)
      {:ok, %{app_key: app_key, app_id: app_id,
              app_secret: app_secret, port: to_integer(port),
              registry_adapter: registry_adapter}}
    rescue
      MatchError -> :invalid_configuration
    end
  end

  defp to_integer(int) when is_binary(int), do: String.to_integer(int)
  defp to_integer(int) when is_integer(int), do: int

  defp run_ssl(dispatch) do
    case Application.fetch_env(:poxa, :ssl) do
      {:ok, ssl_config} ->
        if Enum.all?([:port, :certfile, :keyfile], &Keyword.has_key?(ssl_config, &1)) do
          ssl_port = Keyword.get(ssl_config, :port)
          Logger.info "Starting Poxa using SSL on port #{ssl_port}"
          {:ok, _} = :cowboy.start_https(:https, 100, ssl_config, [env: [dispatch: dispatch] ])
          :ok
        else
          msg = "Must specify port, certfile and keyfile (cacertfile optional)"
          Logger.error msg
          {:error, msg}
        end
      :error ->
        msg = "SSL not configured/started"
        Logger.info msg
        {:error, msg}
    end
  end
end
