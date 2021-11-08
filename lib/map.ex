defmodule ExAudit.Map do
  def ensure(%{__struct__: _} = struct), do: Map.from_struct(struct)
  def ensure(data), do: data
end
