defmodule Fsm do
  @moduledoc """
  Module for representing the elevator as a Finite State Machine.
  """
  use GenServer, restart: :permanent
  require Logger
  @topFloor Application.compile_env(:elevator, :topFloor)
  @waitTimeOnFloor Application.compile_env(:elevator, :waitTimeOnFloor)
  @motorTimeout Application.compile_env(:elevator, :motorTimeout)

  # Public functions
  # --------------------------------------------

  @doc "Checks which floor the elevator is actually in. Starts the `Fsm` at the given floor in idle, or as on an unknown floor in a downwards direction if the elevator is between floors. For use in a supervision tree, see `Supervisor`."
  def start_link([]) do
    {direction, floor} =
      case Driver.get_floor_sensor_state() do
        :between_floors -> {:down, :unknownFloor}
        floor -> {:idle, floor}
      end

    GenServer.start_link(__MODULE__, [{direction, floor}], name: __MODULE__)
  end

  @doc "Initializes the `Fsm`, checking which floor the elevator is at and setting the motor direction downwards if it is between floors."
  def init([{dir, floor}]) do
    Driver.set_door_open_light(:off)
    unless floor == :unknownFloor, do: floorReached(floor), else: Driver.set_motor_direction(dir)

    availabilityCheckTimestamp = :os.system_time(:milli_seconds)

    if dir != :idle,
      do:
        Process.send_after(
          __MODULE__,
          {:availabilityCheck, availabilityCheckTimestamp},
          @motorTimeout
        )

    {:ok, {dir, floor, {:unavailable, availabilityCheckTimestamp}}}
  end

  # Makes sure the motor gets set to stop if the Fsm suddenly terminates
  def terminate(_, _state), do: Driver.set_motor_direction(:stop)

  # API
  # --------------------------------------------

  @doc "Signals to the `Fsm` to wake up from idle state."
  def wakeUp(), do: GenServer.cast(__MODULE__, :wakeUp)

  @doc "Signals to the `Fsm` that a floor is reached."
  def floorReached(floor), do: GenServer.cast(__MODULE__, {:floorReached, floor})

  @doc "Requests the current state of all the `Fsm`s."
  def getStates(nodes \\ [node() | Node.list()]),
    do: GenServer.multi_call(nodes, __MODULE__, :getState)

  # Calls/Casts
  # --------------------------------------------

  # Handles the Fsm being woken up from idle state. The order handler will do this when a new order is added to an empty queue.
  def handle_cast(:wakeUp, {:idle, floor, motorState}) do
    # getting woken up from idle when there is a new order, one can act just as if one has just reached the floor one is currently on
    floorReached(floor)
    {:noreply, {:idle, floor, motorState}}
  end

  def handle_cast(:wakeUp, {direction, floor, motorState}),
    do: {:noreply, {direction, floor, motorState}}

  # Handles the Fsm being informed that a new floor has been reached, triggering handling of any orders on the given floor/direction and setting the elevator motor to the direction of the next order.
  def handle_cast({:floorReached, floor}, {direction, lastFloor, _motorState}) do
    # if we're at an endpoint, we want to switch direction in any case. if the elevator was initialized between floors, we just want to get to nearest floor.
    Driver.set_floor_indicator(floor)

    safeDirection =
      case {lastFloor, floor} do
        {:unknownFloor, _floor} -> :idle
        {_lastFloor, 0} when direction != :idle -> :up
        {_lastFloor, @topFloor} when direction != :idle -> :down
        _ -> direction
      end

    # if there are orders on floor, handle the orders (by waiting)
    if OrderHandler.ordersOnFloor?(floor, safeDirection), do: serveFloor(floor)

    newDirection =
      case OrderHandler.floorForNextOrder?() do
        nil -> :idle
        nextFloor -> getDirectionFromFloors(floor, nextFloor)
      end

    newDirection
    |> motorDirectionFromTravelDirection()
    |> Driver.set_motor_direction()

    availabilityCheckTimestamp = :os.system_time(:milli_seconds)

    Process.send_after(
      __MODULE__,
      {:availabilityCheck, availabilityCheckTimestamp},
      @motorTimeout
    )

    {:noreply, {newDirection, floor, {:available, availabilityCheckTimestamp}}}
  end

  # Handles the Fsm checking if it's gotten to a new floor in a reasonable amount of time if it's not idle.
  # If not, it's taken to mean that the elevator is unavailable, e.g. the motor is disabled.
  def handle_info(
        {:availabilityCheck, timestamp},
        {direction, floor, {:available, timestamp}}
      )
      when direction != :idle do
    Logger.info("motor is disabled!")
    {:noreply, {direction, floor, {:unavailable, nil}}}
  end

  def handle_info({:availabilityCheck, _timestamp}, state), do: {:noreply, state}

  def handle_call(:getState, _from, state), do: {:reply, state, state}

  # Private Functions
  # --------------------------------------------

  defp getDirectionFromFloors(currentFloor, goalFloor) do
    cond do
      goalFloor == nil -> :idle
      goalFloor > currentFloor -> :up
      goalFloor < currentFloor -> :down
      goalFloor == currentFloor -> :idle
    end
  end

  defp motorDirectionFromTravelDirection(travelDirection) do
    case travelDirection do
      :idle -> :stop
      _ -> travelDirection
    end
  end

  defp serveFloor(floor) do
    Driver.set_motor_direction(:stop)
    Driver.set_door_open_light(:on)

    # finish orders at once one gets there, then finish any orders that may have come in the meantime.
    OrderHandler.finishedOrdersOnFloor(floor)
    :timer.sleep(@waitTimeOnFloor)
    OrderHandler.finishedOrdersOnFloor(floor)
    Driver.set_door_open_light(:off)
  end
end
