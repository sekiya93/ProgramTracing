def it003(a)
  i = 1
  s = 0
  while i <= a do
    if i > 3 then
      s = s + 2
    else
      s = s - 1
    end
    i = i + 1
  end
  p s
end
