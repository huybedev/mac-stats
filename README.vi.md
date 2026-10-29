# MacStats

**Tiếng Việt** | [English](README.md) | [简体中文](README.zh.md)

Ứng dụng Swift theo dõi hệ thống trên thanh menu macOS, tích hợp MacFan thành tính năng **Fan Control** ngay trong cùng ứng dụng.

![Giao diện theo dõi trên thanh menu MacStats](screenshot.png)

## Tính năng

- Hiển thị mức sử dụng CPU, RAM, tốc độ tải lên/tải xuống và nhiệt độ CPU trên thanh menu.
- Xem nhiệt độ CPU trung bình, cảm biến CPU nóng nhất và nhiệt độ pin khi máy hỗ trợ.
- Xem các ứng dụng dùng nhiều CPU/RAM nhất; tiến trình phụ được gộp theo ứng dụng cha.
- Tùy chỉnh các cột hiển thị, °C/°F, nhiệt độ trung bình/nóng nhất và chu kỳ thống kê 1/2/5 giây.
- Khởi động khi đăng nhập, mở nhanh Activity Monitor và quản lý cập nhật bản phát hành.
- **Fan Control:** theo dõi nhiệt độ CPU/GPU, RPM hiện tại và mục tiêu, đặt RPM cố định, chỉnh đường nhiệt CPU, chọn Êm/Cân bằng/Mát và xem lịch sử nhiệt độ tối đa ba phút.
- Cửa sổ Fan Control hỗ trợ Tiếng Việt, English và 简体中文. Menu thống kê chính dùng tiếng Anh.

## Yêu cầu

| Thành phần | Yêu cầu |
| --- | --- |
| Theo dõi hệ thống | macOS 11+, Intel hoặc Apple Silicon; cảm biến phụ thuộc mẫu máy |
| Fan Control | macOS 14+, dòng Apple M4; danh sách cảm biến kế thừa đã được kiểm trên Mac mini M4, các mẫu khác chưa xác minh |
| Thay đổi tốc độ quạt | Cài bộ trợ giúp đi kèm và xác thực quyền quản trị qua macOS |
| Build | macOS có Xcode Command Line Tools và SDK macOS 14+; Python 3 để tạo biểu tượng |

Ứng dụng và helper được build universal `arm64` + `x86_64`. Fan Control bị vô hiệu hóa trên máy không hỗ trợ; tính năng thống kê vẫn hoạt động. Dự án dùng framework hệ thống, không cần project Xcode hay gói Swift bên ngoài.

## Build và chạy

Build từ repository này để dùng bản tích hợp Fan Control:

```sh
git clone https://github.com/huybedev/mac-stats.git
cd mac-stats
./build.sh
open MacStats.app
```

Để build, thay thế `/Applications/MacStats.app` và mở ứng dụng trong một bước, chạy từ thư mục source:

```sh
./install.sh
```

Bạn cần quyền ghi vào `/Applications`. Khi chạy trong source, `install.sh` build mã local, không tải bản phát hành. Ứng dụng chạy trên thanh menu, không có biểu tượng Dock. Bấm chuột trái hoặc phải vào các chỉ số để mở menu.

## Sử dụng Fan Control

1. Chọn **Fan Control…** trong menu MacStats. Bạn có thể theo dõi nhiệt độ và RPM khi chưa cài helper.
2. Chọn **Cài bộ trợ giúp**, rồi xác thực ở hộp thoại quản trị macOS để bật điều khiển.
3. Chọn **macOS tự quản lý**, **Theo nhiệt độ CPU** hoặc **RPM cố định**. Chỉnh đường nhiệt hoặc mục tiêu, rồi bấm **Áp dụng**. Cấu hình được lưu sau khi áp dụng thành công.
4. Bấm **Trả về macOS** để nhả điều khiển. Đóng cửa sổ vẫn giữ MacStats và điều khiển quạt hoạt động; thoát ứng dụng sẽ yêu cầu trả quyền về macOS.

Chọn Tiếng Việt, English hoặc 简体中文 tại **Ngôn ngữ** trong cửa sổ. **Launch at Login** nằm trong menu MacStats chính. **Tự bật đường nhiệt khi mở** mặc định tắt; chỉ bật sau khi đã áp dụng đường nhiệt phù hợp. Nếu không bật, điều khiển chỉ bắt đầu khi bạn áp dụng cấu hình. Khi đang điều khiển, MacStats giữ heartbeat khỏi bị App Nap làm trễ nhưng vẫn cho phép máy ngủ. Sau khi thức, app áp dụng lại cấu hình đã áp dụng thành công gần nhất, không dùng chỉnh sửa chưa lưu. Cấu hình đã áp dụng được giữ khi app còn chạy: sau ngủ, mất kết nối hoặc watchdog, app tự thử tiếp tục khi cảm biến hợp lệ và quạt ở Auto. Lần thử thất bại cách nhau 30 giây. Chọn trả về macOS hoặc thoát app sẽ hủy tự tiếp tục.

Đường nhiệt dùng độ C và cảm biến CPU nóng nhất. Phần trăm được quy đổi theo dải phần cứng của từng quạt: 0% là RPM tối thiểu, 100% là tối đa; nội suy tuyến tính giữa các mốc. Nhu cầu làm mát tăng được đáp ứng ngay, giảm tối đa 150 RPM mỗi chu kỳ hai giây. RPM cố định cũng bị giới hạn theo từng quạt. Cửa sổ cập nhật mỗi hai giây, độc lập với chu kỳ thống kê.

### Bộ trợ giúp và phục hồi

Helper dùng dịch vụ XPC riêng, chỉ cung cấp đọc trạng thái, áp dụng cấu hình có giới hạn và nhả quyền. App và helper xác minh chữ ký của nhau. Sau khi thay hoặc cập nhật MacStats, chọn **Cập nhật bộ trợ giúp** để đồng bộ chữ ký tin cậy. Helper này tách biệt với MacFan độc lập; hãy đưa MacFan hoặc phần mềm chỉnh quạt khác về Auto trước khi chuyển sang.

CPU hoặc GPU từ 90°C yêu cầu tốc độ tối đa ở cả hai chế độ tùy chỉnh. Khi thoát, mất kết nối, mất heartbeat quá 12 giây, lỗi cảm biến/đọc/ghi hoặc máy ngủ, helper thử trả quyền về macOS. Nhật ký phục hồi cho phép thử lại sau lỗi hoặc khi helper khởi động lại. Cơ chế này không bảo đảm xử lý được lỗi firmware hoặc mất điện. Bản tích hợp chưa được kiểm ghi quạt thật, ngủ/thức và quá nhiệt thực tế.

Các tệp helper được cài:

```text
/Library/PrivilegedHelperTools/com.openhoangnc.macstats.FanHelper
/Library/LaunchDaemons/com.openhoangnc.macstats.FanHelper.plist
/Library/Application Support/MacStats/FanControl/
```

Chọn **Gỡ bộ trợ giúp…** để gỡ riêng phần điều khiển, vẫn giữ theo dõi. Nếu chưa xác nhận quạt trở về macOS, trình gỡ giữ helper và nhật ký để thử phục hồi tiếp. Bản build local ký ad hoc, chưa được Apple notarize.

## Cập nhật

Bản phát hành kiểm tra cập nhật mỗi ngày. **Install Updates Automatically** quyết định tự cài; **Check for Updates…** kiểm tra thủ công. Bản build local có phiên bản `0.0.0` và không tự kiểm tra cập nhật.

Nguồn tải trong `install.sh`, bộ cập nhật và mục **GitHub Repository** hiện vẫn trỏ về dự án gốc [openhoangnc/mac-stats](https://github.com/openhoangnc/mac-stats), không theo dõi thay đổi Fan Control của fork này. Dùng cách build từ source ở trên để giữ tính năng tích hợp; cài thủ công bản phát hành từ upstream có thể thay thế nó.

## Gỡ cài đặt

Chạy một trong hai lệnh từ source:

```sh
./uninstall.sh
# hoặc
./install.sh --uninstall
```

Các script nhắm tới `/Applications/MacStats.app`: dừng app của người dùng hiện tại, hủy khởi động khi đăng nhập, gỡ helper MacStats đã cài sau xác thực quản trị, xóa ứng dụng và thiết lập của người dùng đó. Nếu phục hồi quạt lỗi, quá trình gỡ dừng và giữ các tệp phục hồi. Với app đặt ngoài `/Applications`, hãy gỡ helper trong cửa sổ, tắt **Launch at Login**, thoát rồi xóa bundle ứng dụng đó.

## Kiểm thử và dòng lệnh

```sh
bash test.sh
```

Lệnh chạy 31 bài kiểm thử hành vi bằng phần cứng giả lập, cùng kiểm tra cú pháp shell và plist. Các bài bao phủ validation, nội suy đường nhiệt, giới hạn RPM, ngưỡng 90°C, quyền sở hữu phiên, watchdog/mất kết nối, lỗi cảm biến/firmware và nhật ký phục hồi; không ghi quạt thật. Bản tích hợp cũng đã đạt build universal, xác minh chữ ký, kiểm tra giao diện và đọc cảm biến thật trên M4. Các kết quả này chưa xác minh điều khiển quạt thật qua helper.

| Lệnh hoặc cờ | Hành vi |
| --- | --- |
| `open MacStats.app --args --fan-control` | Mở Fan Control khi khởi chạy trên máy hỗ trợ; nếu MacStats đang chạy, mở từ menu |
| `MacStats.app/Contents/Resources/MacStatsFanHelper --probe` | In JSON nhiệt độ và trạng thái quạt, chỉ đọc |
| `--cleanup-login-item`, `--uninstall-login-item`, `--uninstall` của binary app | Hủy khởi động khi đăng nhập rồi thoát; không xóa ứng dụng hoặc helper |

## Phát hành

[`.github/workflows/release.yml`](.github/workflows/release.yml) build và phát hành `MacStats.zip` khi push tag `v*`, chạy thủ công hoặc push lên `main` có thông điệp commit chứa `[deploy-prod]`. Push thông thường không phát hành; push chỉ sửa Markdown bị loại trừ. Workflow đóng dấu phiên bản, build app/helper universal và đính kèm archive vào GitHub Release.

## Nguồn và giấy phép

Fork này phát triển từ [MacStats](https://github.com/openhoangnc/mac-stats), tích hợp phần triển khai MacFan local. Mã SMC cho quạt có phần dựa trên Stats theo MIT; ghi nhận tác giả và giấy phép được giữ tại [FanControl/Resources/Stats-LICENSE.txt](FanControl/Resources/Stats-LICENSE.txt) và đóng gói cùng ứng dụng.
