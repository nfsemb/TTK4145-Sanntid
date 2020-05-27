defmodule Output do
  @moduledoc """
    A module that passes button presses and floor changes as messages, abstracting away the polling of memory-mapped IO to fit into the message-passing paradigm.
  """

  use Supervisor
  require Driver
  require Button
  @topFloor Application.compile_env(:elevator, :topFloor)

  # Public functions
  # --------------------------------------------

  @doc "Starts a `Supervisor` for the polling tasks. To be used in a supervision tree."
  def start_link([]), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Initilializes the `Supervisor` by starting up tasks for monitoring all the buttons and the floor sensor."
  def init([]) do
    button_poller =
      all_buttons()
      |> Enum.map(fn button ->
        Supervisor.child_spec({ButtonPoller, button}, id: {ButtonPoller, button})
      end)

    children = [{FloorSensorPoller, []} | button_poller]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private Functions
  # --------------------------------------------

  # all_buttons/1 takes an button_type in [:hall_up, :hall_down, :cab] as input and returns all possible outputs of that type
  defp all_buttons(button_type) do
    floor_map = %{
      down: 1..@topFloor,
      cab: 0..@topFloor,
      up: 0..(@topFloor - 1)
    }

    floor_map[button_type] |> Enum.map(fn floor -> %{floor: floor, type: button_type} end)
  end

  # all_buttons/0 returns all possible orders in the system
  defp all_buttons() do
    Button.valid_button_types()
    |> Enum.map(fn type -> all_buttons(type) end)
    |> List.flatten()
  end
end
