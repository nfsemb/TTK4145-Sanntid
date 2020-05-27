defmodule CostFunction do
  @moduledoc """
  A module for calculating the cost of taking a new order.
  """
  @timeBetweenFloors Application.compile_env(:elevator, :timeBetweenFloors)
  @waitTimeOnFloor Application.compile_env(:elevator, :waitTimeOnFloor)

  # Public functions
  # --------------------------------------------

  def calculate({_newFloor, _buttonType}, _orderQueue, :unknownFloor, _availability), do: Inf

  @doc "Calculates the cost of taking a new order (as button press) given the current queue of orders."
  def calculate({newFloor, buttonType}, orderQueue, floor, availability)
      when buttonType != :cab do
    cond do
      availability == :unavailable ->
        Inf

      Enum.any?(orderQueue, fn {floor, _, _} -> floor == newFloor end) ->
        0

      true ->
        fullOrderQueue = [{newFloor, buttonType, node()} | orderQueue] |> Enum.reverse()
        calculateCostRec(fullOrderQueue, floor)
    end
  end

  # Private functions
  # --------------------------------------------

  # Calculates recursively the cost (time) of handling a given orderQueue if the elevator is currently on a given floor.
  defp calculateCostRec([], _) do
    0
  end

  defp calculateCostRec(orderQueue, startFloor) do
    [nextOrder | _] = orderQueue
    {nextFloor, _, _} = nextOrder

    travelDirection =
      with floorDiff <- nextFloor - startFloor do
        cond do
          floorDiff < 0 -> :down
          floorDiff > 0 -> :up
          floorDiff == 0 -> :idle
        end
      end

    intermediateStoppingFloors =
      orderQueue
      |> Enum.filter(fn {floor, orderType, _} ->
        floor in startFloor..nextFloor && !(floor in [startFloor, nextFloor]) &&
          orderType in [travelDirection, :cab]
      end)
      |> Enum.map(fn {floor, _, _} -> floor end)
      |> Enum.uniq()

    stoppingFloors = [nextFloor | intermediateStoppingFloors]
    floorsTraveled = abs(nextFloor - startFloor)
    floorsWaitedOn = Enum.count(stoppingFloors)

    remainingOrderQueue = Enum.reject(orderQueue, fn {floor, _, _} -> floor in stoppingFloors end)

    @timeBetweenFloors * floorsTraveled + @waitTimeOnFloor * floorsWaitedOn +
      calculateCostRec(remainingOrderQueue, nextFloor)
  end
end
