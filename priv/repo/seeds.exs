summary = Aludel.DemoData.run!(env: Mix.env())

IO.puts("✓ Demo data ready")

Enum.each(summary, fn {name, count} ->
  IO.puts("  #{name}: #{count}")
end)
