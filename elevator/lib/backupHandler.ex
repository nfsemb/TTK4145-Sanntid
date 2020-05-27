defmodule BackupHandler do
  @moduledoc """
  A module for keeping and periodically synchronizing a log of all orders not yet finished in the distributed system.
  """
  use GenServer, restart: :permanent
  require Logger
  @backupRate Application.compile_env(:elevator, :backupRate)

  # Public functions
  # --------------------------------------------

  @doc "Starts the Backup Handler in a supervision tree, see `Supervisor`."
  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Initializes the Backup Handler by starting a periodic call to `multiTriggerLogPush/0`."
  def init(log) do
    # Sends itself a nudge immediately, to attempt synchronization with other BackupHandlers. After a crash, this amounts to getting the backup from the other nodes.
    send(__MODULE__, :routineSync)
    {:ok, log}
  end

  # API
  # --------------------------------------------

  @doc "Requests the `BackupHandler` to do a backup of an order."
  def backupOrder(order), do: GenServer.multi_call(__MODULE__, {:backupOrder, order})

  @doc "Signals to the `BackupHandler` that a floor has been cleared, which triggers a deletion of all orders in the `BackupHandler`s handled by the signalling node."
  def floorFinished(floor), do: GenServer.multi_call(__MODULE__, {:floorFinished, floor, node()})

  @doc "Triggers all `BackupHandler`s to push their list of orders to the other n-1 `BackupHandler`s, effectively synchronizing the `BackupHandler`s."
  def multiTriggerLogPush, do: GenServer.abcast(__MODULE__, :triggerLogPush)

  @doc "Requests a queue of all orders from the `BackupHandler`s, filtering out metadata and returning a list of orders chronologically sorted."
  def requestBackup() do
    {replies, _bad_nodes} = GenServer.multi_call(__MODULE__, :requestBackup)

    replies
    |> Enum.map(fn {_nodeID, log} -> log end)
    |> mergeLogs()
    |> Enum.filter(fn {_timestamp, entryType, _entry} -> entryType == :order end)
    |> Enum.map(fn {_timestamp, :order, entry} -> entry end)
    |> Enum.filter(fn {_floor, _orderType, handledBy} -> handledBy == node() end)
  end

  # Calls/Casts
  # --------------------------------------------

  # Handles the BackupHandler being asked to back up a new order.
  # If the structure of the order and the types of the fields are correct, add the order to the log with a timestamp. Returns :ok or :error.
  def handle_call({:backupOrder, order}, _from, log) do
    with {floor, orderType, handledBy} <- order do
      if is_integer(floor) && orderType in [:up, :down, :cab] &&
           is_atom(handledBy) do
        {:reply, :ok, [{:os.system_time(:milli_seconds), :order, order} | log]}
      else
        {:reply, :error, log}
      end
    else
      _ -> {:reply, :error, log}
    end
  end

  # Handles the BackupHandler being informed that the orders on a floor handled by a given node is finished.
  # Deletes all orders on the given floor by given node, and inserts a "floor finished" token to avoid erroneously re-adding them during synchronization procedures.
  def handle_call({:floorFinished, floor, elevatorNode}, _from, log) do
    # Anonymous function which returns true if the given log entry is an order on the given floor.
    orderOnFloor? = fn logEntry, floor ->
      with {_timestamp, :order, {orderFloor, _orderType, handledBy}} <- logEntry do
        handledBy == elevatorNode && orderFloor == floor
      else
        {_, :floorFinished, _} ->
          false
      end
    end

    filtered_log =
      log
      |> Enum.reject(fn logEntry -> orderOnFloor?.(logEntry, floor) end)
      |> Enum.reject(fn {_timestamp, entryType, entry} ->
        entryType == :floorFinished && entry == {floor, elevatorNode}
      end)

    {:reply, :ok,
     [{:os.system_time(:milli_seconds), :floorFinished, {floor, elevatorNode}} | filtered_log]}
  end

  # Handles someone pushing their log to the BackupHandler, by merging the two logs.
  def handle_cast({:pushLog, remoteLog}, localLog),
    do: {:noreply, mergeLogs([remoteLog, localLog])}

  # Handles someone triggering a log push from the BackupHandler, pushing its log to all other reachable BackupHandlers.
  def handle_cast(:triggerLogPush, log) do
    GenServer.abcast(Node.list(), __MODULE__, {:pushLog, log})
    {:noreply, log}
  end

  def handle_call(:requestBackup, _from, log), do: {:reply, log, log}

  # Gets a nudge to start a routine synchronization procedure with the other backupHandlers
  def handle_info(:routineSync, log) do
    # Trigger log pushing in all backup handlers, which constitutes a full synchonization
    multiTriggerLogPush()

    # To attempt syncing with other servers after a certain time.
    Process.send_after(__MODULE__, :routineSync, @backupRate)
    {:noreply, log}
  end

  # Private functions
  # --------------------------------------------

  # Merges logs, using the floorFinished tokens to avoid erroneously keeping outdated log entries.
  defp mergeLogs(logList) do
    # Concatenate log so that newer entries are first, then older entires.
    concattedLog =
      logList
      |> Enum.concat()
      |> Enum.uniq()
      |> Enum.sort(fn logEntry1, logEntry2 -> logEntry1 >= logEntry2 end)

    floorFinishedList =
      concattedLog
      |> Enum.filter(fn {_timestamp, type, _} -> type == :floorFinished end)
      |> Enum.map(fn {timestamp, :floorFinished, {floor, elevatorNode}} ->
        {timestamp, floor, elevatorNode}
      end)

    # Tells whether a given order ocurred before a clearing of the floor or not.
    beforeFloorfinished? = fn logEntry, clearanceList ->
      with {orderTimestamp, :order, {orderFloor, _, _, handledBy}} <- logEntry,
           {clearanceTimestamp, _, _} <-
             Enum.find(clearanceList, fn {_timestamp, floor, elevatorNode} ->
               {floor, elevatorNode} == {orderFloor, handledBy}
             end) do
        orderTimestamp < clearanceTimestamp
      else
        _ -> false
      end
    end

    # Removes all orders that were in fact cleared from the merged log and returns it.
    concattedLog
    |> Enum.reject(fn logEntry -> beforeFloorfinished?.(logEntry, floorFinishedList) end)
    |> Enum.uniq()
  end
end
