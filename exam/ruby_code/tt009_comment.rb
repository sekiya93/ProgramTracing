# -*- coding: utf-8 -*-
def tt009(c)
  i = 0
  q = 0
  while q < 6 do  # あとで
    if c[i] == 0 then
      if q == 0 then
        # 開始前: 引き続き右に移動して，1 を探す
        i = i + 1
        q = 0
      elsif q == 1 then
        # 0 があったので，書き込み準備
        i = i + 1
        q = 2
      elsif q == 2 then
        # 書込可を見つけて，書込
        c[i] = 1
        i = i - 1
        q = 3
      elsif q == 3 then
        # 余白を見つけた状態
        i = i - 1
        q = 4
      elsif q == 4 then
        # 番兵をリセット
        c[i] = 1
        i = i + 1
        q = 5
      elsif q == 5 then
        q = 6
      end
    else
      if q == 0 then
        # 作業開始: 番兵として 0 に切替
        c[i] = 0
        i = i + 1
        q = 1
      elsif q == 1 then
        # 0 を探す
        i = i + 1
        q = 1
      elsif q == 2 then
        # 引き続き書き込み可能な場所を探す
        i = i + 1
        q = 2
      elsif q == 3 then
        # 引き続き戻る
        i = i - 1
        q = 3
      elsif q == 4 then
        # 引き続き戻る
        i = i - 1
        q = 4
      elsif q == 5 then
        # 作業開始: 番兵として 0 に切替
        c[i] = 0
        i = i + 1
        q = 1
      end
    end
    printf("(q, i, c) = (%d, %d, %s)\n", q, i, c.to_s)
  end
  p c
end

tt009([0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
