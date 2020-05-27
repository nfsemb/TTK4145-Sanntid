defmodule Driver do
  @moduledoc false
  # Given in the course/project resources. Some augmentations have been made, these are commented on in where they occur the source code.
  use GenServer, restart: :permanent

  # Macros
  # --------------------------------------------
  @call_timeout 1000
  @button_map %{:up => 0, :down => 1, :cab => 2}
  @state_map %{:on => 1, :off => 0}
  @direction_map %{:up => 1, :down => 255, :stop => 0}

  # Public Functions
  # --------------------------------------------

  def start_link([]), do: start_link([{127, 0, 0, 1}, 15657])

  def start_link([address, port]),
    do: GenServer.start_link(__MODULE__, [address, port], name: __MODULE__)

  def stop, do: GenServer.stop(__MODULE__)

  def init([address, port]),
    do: {:ok, socket} = :gen_tcp.connect(address, port, [{:active, false}])

  def terminate(_, socket) do
    :gen_tcp.close(socket)
    {:ok, socket}
  end

  # User API
  # --------------------------------------------

  # direction can be :up/:down/:stop
  def set_motor_direction(direction),
    do: GenServer.cast(__MODULE__, {:set_motor_direction, direction})

  # button_type can be :up/:down/:cab
  # state can be :on/:off

  # slightly modified to be able to set order lights on other nodes
  def set_order_button_light(nodeList \\ [node()], button_type, floor, state),
    do:
      GenServer.abcast(nodeList, __MODULE__, {:set_order_button_light, button_type, floor, state})

  def set_floor_indicator(floor), do: GenServer.cast(__MODULE__, {:set_floor_indicator, floor})

  # state can be :on/:off
  def set_door_open_light(state), do: GenServer.cast(__MODULE__, {:set_door_open_light, state})

  def get_order_button_state(floor, button_type),
    do: GenServer.call(__MODULE__, {:get_order_button_state, floor, button_type})

  def get_floor_sensor_state, do: GenServer.call(__MODULE__, :get_floor_sensor_state)

  # Casts
  # --------------------------------------------
  def handle_cast({:set_motor_direction, direction}, socket) do
    :gen_tcp.send(socket, [1, @direction_map[direction], 0, 0])
    {:noreply, socket}
  end

  def handle_cast({:set_order_button_light, button_type, floor, state}, socket) do
    :gen_tcp.send(socket, [2, @button_map[button_type], floor, @state_map[state]])
    {:noreply, socket}
  end

  def handle_cast({:set_floor_indicator, floor}, socket) do
    :gen_tcp.send(socket, [3, floor, 0, 0])
    {:noreply, socket}
  end

  def handle_cast({:set_door_open_light, state}, socket) do
    :gen_tcp.send(socket, [4, @state_map[state], 0, 0])
    {:noreply, socket}
  end

  # Calls
  # --------------------------------------------
  def handle_call({:get_order_button_state, floor, order_type}, _from, socket) do
    :gen_tcp.send(socket, [6, @button_map[order_type], floor, 0])

    button_state =
      case :gen_tcp.recv(socket, 4, @call_timeout) do
        {:ok, [6, 1, 0, 0]} -> :on
        {:ok, [6, 0, 0, 0]} -> :off
      end

    {:reply, button_state, socket}
  end

  def handle_call(:get_floor_sensor_state, _from, socket) do
    :gen_tcp.send(socket, [7, 0, 0, 0])

    sensor_state =
      case :gen_tcp.recv(socket, 4, @call_timeout) do
        {:ok, [7, 0, _, 0]} -> :between_floors
        {:ok, [7, 1, floor, 0]} -> floor
      end

    {:reply, sensor_state, socket}
  end
end
