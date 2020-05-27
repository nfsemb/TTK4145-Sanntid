defmodule OrderHandler do
  @moduledoc """
  A module for keeping track of the orders being handled by a specific elevator.
  """
  # order is on the form {floor, orderType, direction, handledBy}
  use GenServer, restart: :permanent
  require Logger
  @topFloor Application.compile_env(:elevator, :topFloor)

  # Public functions
  # --------------------------------------------

  def init(orderQueue) do
    # clear all lights locally
    Enum.map(0..@topFloor, fn floor -> clearFloorLights(floor, :local) end)
    # set the lights of orders to be handled
    orderQueue
    |> Enum.map(fn {floor, type, _handledBy} ->
      Driver.set_order_button_light(type, floor, :on)
    end)

    {:ok, orderQueue}
  end

  @doc "Requests backup from the `BackupHandler`s and starts the `OrderHandler` in a supervision tree, see `Supervisor`."
  def start_link([]) do
    ordersFromBackup = extractBackup()
    unless ordersFromBackup == [], do: Fsm.wakeUp()

    GenServer.start_link(__MODULE__, ordersFromBackup, name: __MODULE__)
  end

  # API
  # --------------------------------------------

  @doc "Asks the `OrderHandler` if there are orders on the given floor."
  def ordersOnFloor?(floor, travelDirection),
    do: GenServer.call(__MODULE__, {:floorOrdersCheck, floor, travelDirection})

  @doc "Signals to the `OrderHandler` that a floor is finished, triggering the deletion of all orders on that floor."
  def finishedOrdersOnFloor(floor),
    do: GenServer.cast(__MODULE__, {:finishedOrdersOnFloor, floor})

  @doc "Asks the `OrderHandler` which floor the next order is on. Returns :tnil if the order queue is empty."
  def floorForNextOrder?, do: GenServer.call({__MODULE__, node()}, :floorForNextOrder)
  @doc "Asks the `OrderHandler` to add the order to the order queue."
  def addOrder(order, node), do: GenServer.abcast([node], __MODULE__, {:addOrder, order})

  @doc "Triggers all the `OrderHandler`s to retrieve backup from the `BackupHandler`s."
  def multiTriggerRetrieveBackup(), do: GenServer.abcast(__MODULE__, :retrieveBackup)

  @doc "Requests the order queue of all the `OrderHandler`s."
  def getOrderQueues(nodes \\ [node() | Node.list()]),
    do: GenServer.multi_call(nodes, __MODULE__, :getOrderQueue)

  # Calls/Casts
  # --------------------------------------------

  # Handles the OrderHandler being asked if there are orders to complete on a given floor, returns a boolean.
  def handle_call({:floorOrdersCheck, _floor, _direction}, _from, []), do: {:reply, false, []}

  def handle_call({:floorOrdersCheck, floor, direction}, _from, orderQueue) do
    compatibleOrderOnFloor? =
      Enum.any?(orderQueue, fn {orderFloor, orderType, _handledBy} ->
        {orderFloor, orderType} in [
          {floor, :cab},
          {floor, direction}
        ]
      end)

    # If the next order is on the given floor, we want to take it even if it is incompatible direction-wise.
    [{nextFloor, _, _} | _remainingOrderQueue] = Enum.reverse(orderQueue)
    nextOrderOnFloor? = floor == nextFloor

    {:reply, compatibleOrderOnFloor? || nextOrderOnFloor?, orderQueue}
  end

  # Handles the OrderHandler being asked for the floor of the next order. Returns nil if there are no more orders.
  def handle_call(:floorForNextOrder, _from, []), do: {:reply, nil, []}

  def handle_call(:floorForNextOrder, _from, orderQueue) do
    [{floorForNextOrder, _buttonType, _handledBy} | _tail] = Enum.reverse(orderQueue)
    {:reply, floorForNextOrder, orderQueue}
  end

  def handle_call(:getOrderQueue, _from, orderQueue), do: {:reply, orderQueue, orderQueue}

  # Handles the OrderHandler being asked to be responsible for a new order.
  # This is safe to do in a cast as all lights and backup are done as a result of the cast, not by the method doing the cast.
  def handle_cast({:addOrder, order}, orderQueue) do
    responseBackupHandler = BackupHandler.backupOrder(order)
    backupCompleted? = serverCallSuccessful?(responseBackupHandler)

    orderWatchCompleted? =
      if backupCompleted? do
        responseOrderWatchdog = OrderWatchdog.addOrder(order)
        serverCallSuccessful?(responseOrderWatchdog)
      end

    if backupCompleted? && orderWatchCompleted? do
      {floor, buttonType, _handledBy} = order

      case buttonType do
        :cab -> Driver.set_order_button_light(buttonType, floor, :on)
        _ -> Driver.set_order_button_light([node() | Node.list()], buttonType, floor, :on)
      end

      if orderQueue == [], do: Fsm.wakeUp()

      {:noreply, [order | orderQueue]}
    else
      {:noreply, orderQueue}
    end
  end

  # Handles the OrderHandler being informed that the orders on a given floor were completed.
  def handle_cast({:finishedOrdersOnFloor, floor}, orderQueue) do
    remainingOrderQueue =
      orderQueue
      |> Enum.reject(fn {orderFloor, _orderType, _orderHandledBy} -> orderFloor == floor end)

    BackupHandler.floorFinished(floor)
    OrderWatchdog.floorFinished(floor)

    clearFloorLights(floor)

    {:noreply, remainingOrderQueue}
  end

  # Handles the OrderHandler being asked to retrieve backup of orders.
  def handle_cast(:retrieveBackup, orderQueue) do
    ordersFromBackup = extractBackup()

    # Concatenate the queues without duplicates, making sure the last element of duplicates (the non-backup one) is being kept.
    fullOrderQueue =
      [ordersFromBackup, orderQueue]
      |> Enum.concat()
      |> Enum.reverse()
      |> Enum.uniq()
      |> Enum.reverse()

    if orderQueue == [] && fullOrderQueue != [], do: Fsm.wakeUp()

    {:noreply, fullOrderQueue}
  end

  # Private functions
  # --------------------------------------------

  # Takes the response from a server multicall (for instance a backup request or orderWatchdog request) and checks if at least one actor responded affirmatively
  defp serverCallSuccessful?({replies, _bad_nodes}) do
    replies
    |> Enum.reject(fn {_elevatorID, repl} -> repl == :error end)
    |> Enum.any?()
  end

  # Requests backup from the BackupHandler, and extracts from the general backup the parts pertaining to the local elevator.
  defp extractBackup() do
    BackupHandler.requestBackup()
    |> Enum.filter(fn {_floor, _type, handledBy} -> handledBy == node() end)
  end

  # Convenience function. Clears hall lights everywhere, clears local cab light.
  defp clearFloorLights(floor, hallClearingScope \\ :global) do
    nodeListHall =
      case hallClearingScope do
        :global -> [node() | Node.list()]
        :local -> [node()]
      end

    Enum.map([:up, :down], fn type ->
      Driver.set_order_button_light(nodeListHall, type, floor, :off)
    end)

    Driver.set_order_button_light(:cab, floor, :off)
    :ok
  end
end
