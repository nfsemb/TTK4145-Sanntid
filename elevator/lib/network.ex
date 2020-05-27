defmodule Network do
  @moduledoc """
    Broadcasting of IP and listening to other IPs.
  """
  use GenServer, restart: :permanent
  require Logger

  @udpPort Application.compile_env(:elevator, :udpPort)
  @broadcastIP Application.compile_env(:elevator, :broadcastIP)
  @broadcastRate Application.compile_env(:elevator, :broadcastRate)

  # Public functions
  # --------------------------------------------

  @doc "Starts the GenServer."
  def start_link([port]), do: GenServer.start_link(__MODULE__, [port], name: __MODULE__)

  @doc "Initialize the GenServer by starting node and opening UDP socket at port `@udpPort`."
  def init([port]) do
    Node.start(getElevatorID(port))
    Node.set_cookie(:chocolatechip)
    baseOptList = [{:broadcast, true}, {:active, true}, {:reuseaddr, true}]

    # In order to reuse a socket/port for udp broadcast, extra options need to be passed for non-linux OS-s (only relevant for multiple elevators on one PC):
    fullOptList =
      case :os.type() do
        {:unix, :darwin} -> [{:raw, 0xFFFF, 0x0200, <<1::32-native>>} | baseOptList]
        {:win32, :nt} -> [{:raw, 0xFFFF, 0x0004, <<1::32-native>>} | baseOptList]
        _ -> baseOptList
      end

    {:ok, socket} = :gen_udp.open(@udpPort, fullOptList)

    # Begin broadcasting loop
    send(self(), :nudge)
    {:ok, socket}
  end

  @doc "Closes the UDP socket upon termination of GenServer."
  def terminate(_, socket) do
    :gen_udp.close(socket)
    Node.stop()
  end

  # API
  # --------------------------------------------

  @doc "Handles broadcasting of UDP messages"
  def handle_info(:nudge, socket) do
    broadcast(socket)

    # Call self again after @broadcastRate[ms]
    Process.send_after(__MODULE__, :nudge, @broadcastRate)

    {:noreply, socket}
  end

  @doc "Handles received UDP messages"
  def handle_info({:udp, _, _, _, nodeIDString}, socket) do
    # Try connect to Node ID
    nodeID =
      nodeIDString
      |> to_string()
      |> String.to_atom()

    unless nodeID in [node() | Node.list()] do
      Logger.info("trying to connect to node #{inspect(nodeID)}")

      connResponse = Node.ping(nodeID)

      if connResponse == :pang do
        Logger.error("Couldn't connect to node #{nodeID}.")
      else
        # get BackupHandler, orderWatchdog and OrderHandler to retrieve the orders, as there may have been orders previously if the node is being restarted
        BackupHandler.multiTriggerLogPush()
        OrderWatchdog.multiTriggerImpatientOrderPush()
        OrderHandler.multiTriggerRetrieveBackup()
      end
    end

    {:noreply, socket}
  end

  # Private Functions
  # --------------------------------------------

  # Broadcasts the IP address to UDP port.
  defp broadcast(socket) do
    msg = to_string(node())
    :gen_udp.send(socket, @broadcastIP, @udpPort, msg)
  end

  # Creates a valid node name by retreiving IP address.
  def getElevatorID(num \\ "") do
    # Gets info about IP addresses and extracts global/local IP
    {:ok, [{ipTuple, _, _} | _tail]} = :inet.getif()
    # Cast IP to correct format
    with {field1, field2, field3, field4} <- ipTuple do
      String.to_atom("gr_x_elevator#{num}@#{field1}.#{field2}.#{field3}.#{field4}")
    end
  end
end
