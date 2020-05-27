defmodule OrderWatchdog do
  @moduledoc """
  A module for keeping track of the hall orders which are underway to being handled, and triggering a resend of orders which stay unhandled for too long.
  """
  use GenServer, restart: :permanent
  require Logger
  @baseWaitingTime Application.compile_env(:elevator, :orderWatchdogWaitingTime)
  @randomInterval Application.compile_env(:elevator, :orderWatchdogRandomInterval)

  # Public functions
  # --------------------------------------------

  @doc "Initializes the `OrderWatchdog` by calling `multiTriggerImpatientOrderPush/0`."
  def init(orders) do
    multiTriggerImpatientOrderPush()
    {:ok, orders}
  end

  @doc "Starts the `OrderWatchdog` in a supervision tree, see `Supervisor`."
  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  # API
  # --------------------------------------------

  @doc "Requests the `OrderWatchdog`s to add an order, and begin a watchdog timer on it for resending."
  def addOrder(order), do: GenServer.multi_call(__MODULE__, {:addOrder, order})

  @doc "Signals to the `OrderWatchdog`s that a floor has been cleared, which triggers a deletion of all orders in the `OrderWatchdog`s handled by the signalling node."
  def floorFinished(floor),
    do: Enum.map([:up, :down, :cab], fn type -> finishedOrder({floor, type, node()}) end)

  @doc "Triggers all `OrderWatchdog`s to push their list of orders to the other n-1 `OrderWatchdog`s, effectively synchronizing the `OrderWatchdog`s."
  def multiTriggerImpatientOrderPush(),
    do: GenServer.abcast(__MODULE__, :triggerImpatientOrderPush)

  # Calls/Casts
  # --------------------------------------------

  # Handles the OrderWatchdog being asked to watch a new order. Sends a delayed message to itself to check on the order.
  def handle_call({:addOrder, newOrder}, _from, orders) do
    unless Enum.any?(orders, fn {_timestamp, order} -> order == newOrder end) do
      newEntry = {:os.system_time(:milli_seconds), newOrder}

      Process.send_after(
        __MODULE__,
        {:orderExpired, newEntry},
        @baseWaitingTime + Enum.random(0..@randomInterval)
      )

      {:reply, :ok, [newEntry | orders]}
    else
      {:reply, :ok, orders}
    end
  end

  # Handles the OrderWatchdog being informed that a given order is finished, triggering it to remove it from its list.
  def handle_cast({:finishedOrder, finishedOrder}, orders) do
    remainingOrders = Enum.reject(orders, fn {_timestamp, order} -> order == finishedOrder end)
    {:noreply, remainingOrders}
  end

  # Handles someone pushing their impatientOrderList to the OrderWatchdog, triggering it to add the discrepancy to its list and watch them.
  def handle_cast({:impatientOrderPush, remoteList}, localList) do
    fullList = mergeOrderLists([remoteList, localList])

    fullList
    |> Enum.reject(fn entry -> entry in localList end)
    |> Enum.map(fn entry ->
      Process.send_after(
        __MODULE__,
        {:orderExpired, entry},
        @baseWaitingTime + Enum.random(0..@randomInterval)
      )
    end)

    {:noreply, fullList}
  end

  # Handles someone triggering an impatient order push from the OrderWatchdog, pushing its list of impatient orders to all other reachable OrderWatchdogs.
  def handle_cast(:triggerImpatientOrderPush, orders) do
    GenServer.abcast(Node.list(), __MODULE__, {:impatientOrderPush, orders})
    {:noreply, orders}
  end

  # Gets a nudge to check whether an expired order has been dealt with in the meantime. If not, it re-issues it as a button press to the OrderDistributor.
  def handle_info({:orderExpired, {timestamp, impatientOrder}}, orderList) do
    if Enum.any?(orderList, fn entry -> entry == {timestamp, impatientOrder} end) do
      finishedOrder(impatientOrder)

      with {floor, type, _handledBy} <- impatientOrder do
        OrderDistributor.buttonPressed({floor, type})
      end
    end

    {:noreply, orderList}
  end

  # Private functions
  # --------------------------------------------

  # Signals to all OrderWatchdogs that a specific impatient order is finished, and should be removed.
  defp finishedOrder(order), do: GenServer.abcast(__MODULE__, {:finishedOrder, order})

  # Merges different order lists, concatenating them and removing duplicates.
  defp mergeOrderLists(orderLists) do
    orderLists
    |> Enum.concat()
    |> Enum.sort(fn el1, el2 -> el1 >= el2 end)
    |> Enum.uniq()
  end
end
