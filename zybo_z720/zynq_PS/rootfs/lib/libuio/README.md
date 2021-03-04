# slab ライブラリ
## 概要
柴田研ロボコンチーム：システム班により制作中のライブラリです。  
主にzynqのPS-PL通信周りを取り扱っています。

## インストール
``` sh
$ sudo apt install -y libboost-dev libboost-python-dev libboost-numpy-dev pkg-config  
$ sudo pip3 install pyconfig
$ make
$ sudo make install
```
## アンインストール
``` sh
$ sudo make uninstall
```

## 使い方
### C++
#### 文法
##### User I/O レジスタへのアクセス
- ヘッダをインクルードする
``` c++
#include <slab/uio.hpp>
```
- `slab::System`クラスの変数を宣言する
  - コンストラクタが`/dev/uio0`へアクセスするため、実行時に`sudo`をつけていないとパーミッションエラーになる
``` c++
slab::System fpga("/dev/uio0");
```
- 指定したアドレスのレジスタ値を取得する
``` c++
fpga.read(int addr)
```
- レジスタの指定したアドレスに、指定した値を書き込む
``` c++
fpga.write(int addr, int data)
```
##### カメラ(OV7670)関連
- opencvのヘッダをインクルードする
``` c++
#include <opencv2/core.hpp>
#include <opencv2/opencv.hpp>
```
- opencvのヘッダをインクルードする
``` c++
#include <opencv2/core.hpp>
#include <opencv2/opencv.hpp>
```
- カメラの設定を初期化する
``` c++
fpga.init_ov7670();
```
- 2値画像のフレームを取得する
  - `front_or_rear`については、フロントカメラの場合は`true`, リアカメラの場合は`false`にする
  - 2値画像のフレームは、`*img`に格納される
``` c++
const int IMG_W = 640, IMG_H = 480;
cv::Mat binary_img(cv::Size(IMG_W, IMG_H), CV_8UC1);
fpga.fetch_binaryFrame(uint8_t* binary_img.data, uint8_t threshold, bool front_or_rear);
```
- 線分情報のフレームを取得する
  - `front_or_rear`については、フロントカメラの場合は`true`, リアカメラの場合は`false`にする
  - 線分情報のフレームは、`slab::Line_t fpga.lines_`に格納される
``` c++
fpga.fetch_lineFrame(f_r);
```
- 取得した線分情報をもとに、線分画像を描画する
``` c++
void draw_lines (cv::Mat& img, const int W, const int H,  std::vector<slab::Line_t> lines) {
	img = cv::Scalar(0,0,0);
	for (int i=0; i<(int)lines.size(); i++) {
		cv::line(img, cv::Point(lines[i].start_h, lines[i].start_v), cv::Point(lines[i].end_h, lines[i].end_v), cv::Scalar(255,255,225), 1);
	}
}

cv::Mat line_img(cv::Size(IMG_W, IMG_H), CV_8UC1);
draw_lines(uint8_t* line_img.data, int IMG_W, int IMG_H, slab::Line_t fpga.lines_);
```
##### モーター制御
- アクセル値を送信
``` c++
fpga.send_accel(int8_t accel);
```
- ステアリング値を送信
``` c++
fpga.send_steer(int8_t steer);
```
- モーターフィードバック値を受信
  - `front_or_rear`については、フロントモーターの場合は`true`, リアモーターの場合は`false`にする
``` c++
uint16_t feedback = fpga.recv_rotation(bool front_or_rear);
```
#### コンパイルと実行
``` sh
$ g++ source.cpp -o exe `pkg-config --libs slab opencv4` 
$ sudo ./exe
```

### python3
#### 文法
##### User I/O レジスタへのアクセス
- slab モジュールをインポートする
``` python3
import slab
```
- zynq の PL をオープンする
  - コンストラクタが`/dev/uio0`へアクセスするため、実行時に`sudo`をつけていないとパーミッションエラーになる
``` python3
fpga = slab.System("/dev/uio0")
```
- 指定したアドレスのレジスタ値を取得する
``` python3
fpga.read(int addr)
```
- レジスタの指定したアドレスに、指定した値を書き込む
``` python3
fpga.write(int addr, int data)
```
##### カメラ(OV7670)関連
- `numpy`と`opencv`をインポートする
``` python3
import numpy as np
import cv2
```
- カメラの設定を初期化する
``` python3
fpga.init_ov7670()
```
- 2値画像のフレームを取得する
  - `front_or_rear`については、フロントカメラの場合は`True`, リアカメラの場合は`False`にする
``` python3
fpga.fetch_binaryFrame(uint8_t threshold, bool front_or_rear)
```
- 線分情報のフレームを取得する
  - `front_or_rear`については、フロントカメラの場合は`True`, リアカメラの場合は`False`にする
``` python3
lines = fpga.fetch_lineFrame(bool front_or_rear)
```
- 取得した線分情報をもとに、線分画像を描画する
``` python3
def draw_lines(img, lines):
    num_of_lines = lines.shape[0]
    img.fill(0)

    for i in range(num_of_lines):
        img = cv2.line (
                img,                        # output img 
                (lines[i][0], lines[i][1]), # start(x, y)
                (lines[i][2], lines[i][3]), # end(x, y)
                (255, 255, 255),            # color
                1                           # thickness [px]
                )

line_img = np.zeros((480, 640, 3), dtype = np.uint8)
draw_lines(line_img, lines)
```
##### モーター制御
- アクセル値を送信
``` python3
fpga.send_accel(int8_t accel)
```
- ステアリング値を送信
``` python3
fpga.send_steer(int8_t steer)
```
- モーターフィードバック値を受信
  - `front_or_rear`については、フロントモーターの場合は`True`, リアモーターの場合は`False`にする
``` python3
uint16_t feedback = fpga.recv_rotation(bool front_or_rear)
```
#### 実行
``` sh
$ sudo python3 source_code.py
```
