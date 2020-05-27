defmodule FloorSensorPoller do
  @moduledoc """
    A module that observes changes in the floor sensor, passing a message on rising flank.
  """
  use Task
  require Driver

  @pollingRate Application.compile_env(:elevator, :pollingRate)

  # Public functions
  # --------------------------------------------

  @doc "Starts a task monitoring the floorsensor"
  def start_link([]) do
    Task.start_link(__MODULE__, :poller, [:between_floors])
  end

  # Recursive function for periodically polling the floor sensor.
  def poller(prev) do
    current = Driver.get_floor_sensor_state()

    case {prev, current} do
      {:between_floors, :between_floors} ->
        nil

      {floor, floor} ->
        nil

      # Floor change
      {:between_floors, floor} ->
        # Sends a update to the fsm that a new floor is reached
        Fsm.floorReached(floor)

      _ ->
        nil
    end

    :timer.sleep(@pollingRate)
    poller(current)
  end
end
