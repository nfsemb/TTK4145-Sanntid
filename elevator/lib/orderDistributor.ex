defmodule OrderDistributor do
  @moduledoc """
  A module for assigning and distributing orders from the local button panel to the most optimal order handler.
  It should be noted that the `OrderDistributor` has no state like a regular `GenServer` would have, but the `GenServer` behavior is still used for casting and calling functionality.
  """
  use GenServer, restart: :permanent
  require Logger

  # Public functions
  # --------------------------------------------

  def init([]), do: {:ok, nil}

  @doc "Starts the `OrderDistributor`, to be used in a supervision tree, see `Supervisor`."
  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  # API
  # --------------------------------------------

  @doc "Informs the `OrderDistributor` that a button was pressed."
  def buttonPressed(buttonPress), do: GenServer.cast(__MODULE__, {:buttonPressed, buttonPress})

  # Calls/Casts
  # --------------------------------------------

  # Handles the OrderDistributor getting informed of a local button press. If the button press is a cab, the distributor assigns it to the local OrderHandler.
  # If not, it collects states of entire visible system, calculates which node has the lowest cost and assigns the order to that node's OrderHandler.
  def handle_cast({:buttonPressed, buttonPress}, nil) do
    {floor, buttonType} = buttonPress

    unless buttonType == :cab do
      {orderQueues, _bad_nodes} = OrderHandler.getOrderQueues()
      {fsmStates, _bad_nodes} = Fsm.getStates()

      lowestCostNode =
        pairReplies(orderQueues, fsmStates)
        # Transform into pairs of nodeIDs and their associated cost of taking the order.
        |> Enum.map(fn {nodeID, {orderQueue, {_dir, floor, {availability, _timestamp}}}} ->
          {nodeID, CostFunction.calculate(buttonPress, orderQueue, floor, availability)}
        end)
        |> getLowestCostNode()

      order = {floor, buttonType, lowestCostNode}
      OrderHandler.addOrder(order, lowestCostNode)
      {:noreply, nil}
    else
      with {[{_nodeID, {_direction, _floor, {availability, _timestamp}}}], _bad_nodes} <-
             Fsm.getStates([node()]) do
        # Only ask the local OrderHandler to add the order if it's available, thus not promising to take new cab orders
        # after unavailability has occurred.
        if availability == :available do
          order = {floor, buttonType, node()}
          OrderHandler.addOrder(order, node())
        end
      end

      {:noreply, nil}
    end
  end

  # Private functions
  # --------------------------------------------

  # Takes in a list of nodes and associated cost, returns the name of the node with the lowest associated cost. If all costs are Inf, returns nil
  defp getLowestCostNode(costList) do
    {lowestCostNode, _cost} =
      costList
      |> Enum.reject(fn {_nodeID, cost} -> cost == Inf end)
      |> Enum.min_by(fn {nodeID, cost} -> {cost, nodeID} end, fn -> nil end)

    lowestCostNode
  end

  # Takes in lists of orderQueues and fsm states along with associated nodeIDs, pairs them and return the pairs with their associated nodeIDs.
  defp pairReplies(orderQueueList, fsmList) do
    orderQueueNodes = Enum.map(orderQueueList, fn {nodeID, _orderQueue} -> nodeID end)
    fsmNodes = Enum.map(fsmList, fn {nodeID, _fsmState} -> nodeID end)
    # List arithmetic black magic for the set intersection operation.
    commonNodes = orderQueueNodes -- orderQueueNodes -- fsmNodes

    commonNodes
    |> Enum.map(fn nodeID -> {nodeID, {orderQueueList[nodeID], fsmList[nodeID]}} end)
  end
end
