defmodule Mijnverbruik.Meter.Reader do
  @moduledoc """
  Reads raw DSMR telegrams from a TCP serial bridge (esp-link, ser2net, ...)
  and broadcasts each valid telegram to `Mijnverbruik.Meter.subscribe/0` subscribers.

  On any socket failure it closes the socket and reconnects after a backoff,
  so an offline meter never exhausts the supervisor's restart budget.
  """
  use GenServer

  require Logger

  alias Mijnverbruik.Meter

  @backoff_ms 2_000
  @connect_timeout_ms 5_000
  # Idle socket longer than this means the bridge or meter has gone silent.
  @recv_timeout_ms 30_000
  # A DSMR 5 telegram is about 1 KB; more than this without a complete one is junk.
  @max_buffer 16_384
  @telegram ~r/\A\/[^!]*![0-9A-Fa-f]{0,4}\r\n/

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    {:ok, %{host: host, port: port, opts: opts, socket: nil, buffer: ""}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    opts = [:binary, active: :once]

    case :gen_tcp.connect(String.to_charlist(state.host), state.port, opts, @connect_timeout_ms) do
      {:ok, socket} ->
        Logger.info("Connected to meter at #{state.host}:#{state.port}")
        {:noreply, %{state | socket: socket}, @recv_timeout_ms}

      {:error, reason} ->
        fail(state, reason)
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    {telegrams, buffer} = split(state.buffer <> data)
    Enum.each(telegrams, &publish/1)
    :ok = :inet.setopts(socket, active: :once)
    {:noreply, %{state | buffer: buffer}, @recv_timeout_ms}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state), do: fail(state, :closed)

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state),
    do: fail(state, reason)

  def handle_info(:timeout, %{socket: socket} = state) when socket != nil,
    do: fail(state, :timeout)

  def handle_info(:reconnect, state), do: {:noreply, state, {:continue, :connect}}
  def handle_info(_stale, state), do: {:noreply, state}

  defp fail(state, reason) do
    Logger.warning("Meter connection #{state.host}:#{state.port} failed: #{inspect(reason)}")
    if state.socket, do: :gen_tcp.close(state.socket)
    Process.send_after(self(), :reconnect, Keyword.get(state.opts, :backoff_ms, @backoff_ms))
    {:noreply, %{state | socket: nil, buffer: ""}}
  end

  defp publish(raw) do
    case DSMR.parse(raw, lenient: true) do
      {:ok, telegram} ->
        Meter.broadcast(telegram)

      {:error, error} ->
        Logger.warning("Skipping invalid telegram: #{Exception.message(error)}")
    end
  end

  @doc """
  Splits a byte buffer into complete telegrams and the unconsumed rest.

  Bytes before the first `/` are discarded; an oversized partial buffer is dropped.
  """
  def split(buffer), do: split(buffer, [])

  defp split(buffer, acc) do
    case :binary.match(buffer, "/") do
      :nomatch ->
        {Enum.reverse(acc), ""}

      {start, _} ->
        buffer = binary_part(buffer, start, byte_size(buffer) - start)

        case Regex.run(@telegram, buffer, return: :index) do
          [{0, len}] ->
            <<telegram::binary-size(len), rest::binary>> = buffer
            split(rest, [telegram | acc])

          nil when byte_size(buffer) > @max_buffer ->
            {Enum.reverse(acc), ""}

          nil ->
            {Enum.reverse(acc), buffer}
        end
    end
  end
end
