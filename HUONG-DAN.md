# ACQ Smarthome · Sổ việc — hướng dẫn triển khai

Ứng dụng web cài được như app trên iOS, Android và máy tính, không qua App Store / Play Store.
Dùng cho chủ và tối đa khoảng 10 nhân viên (gói miễn phí của Supabase và Vercel đủ dùng).

## Các file trong gói

| File | Vai trò |
|---|---|
| `index.html` | Toàn bộ ứng dụng (giao diện + logic) |
| `config.js` | Nơi dán khóa kết nối Supabase |
| `schema.sql` | Lược đồ cơ sở dữ liệu + phân quyền, chạy một lần trên Supabase |
| `manifest.json`, `sw.js`, `icon*.png/svg` | Để cài như app và mở được khi mất mạng |

## Bước 1 — Tạo cơ sở dữ liệu (Supabase, 10 phút)

1. Vào https://supabase.com → đăng ký bằng email → **New project** (đặt tên, mật khẩu DB, region *Singapore*).
2. Menu trái **SQL Editor** → **New query** → dán toàn bộ nội dung `schema.sql` → **Run**.
3. Menu **Authentication → Users → Add user → Create new user**: nhập email + mật khẩu cho chủ cửa hàng (bật *Auto Confirm User*).
4. Quay lại **SQL Editor**, chạy (thay email cho đúng):
   ```sql
   update users set role='owner', name='Tên chủ cửa hàng' where email='email-cua-chu@gmail.com';
   ```
5. **Project Settings → API**: chép **Project URL** và khóa **anon public**, dán vào `config.js`:
   ```js
   window.APP_CONFIG = { supabaseUrl: "https://xxxx.supabase.co", supabaseKey: "eyJ..." };
   ```
6. (Tuỳ chọn) **Authentication → Providers → Email**: tắt *Confirm email* để tạo tài khoản nhân viên không cần xác nhận.

Thêm nhân viên: **Authentication → Users → Add user** (email + mật khẩu), rồi trong ứng dụng vào **Nhân sự** sửa tên, SĐT, vai trò.

## Bước 1b — Thông báo đẩy (Supabase Edge Function, 5 phút)

Thông báo *trong app* chạy ngay sau Bước 1 (realtime). Để nhận cả khi **app đã đóng** (Web Push, có cả iPhone đã "Thêm vào MH chính"):
1. Supabase → **Edge Functions → Deploy a new function → Via Editor**: tên `send-push`, dán nội dung `supabase/functions/send-push/index.ts` → Deploy. Tắt "Verify JWT" nếu có tùy chọn (hoặc giữ, vì trigger đã gửi kèm khóa anon).
2. Trong function → **Secrets**: thêm `VAPID_PUBLIC_KEY` và `VAPID_PRIVATE_KEY` (2 dòng trong `supabase/VAPID.txt`). `SUPABASE_URL` và `SUPABASE_SERVICE_ROLE_KEY` có sẵn.
3. Trong `schema.sql`, phần cuối "Gửi Web Push": thay `<PROJECT_REF>` (phần trước `.supabase.co` của Project URL) và `<ANON_KEY>` rồi chạy đoạn đó trong SQL Editor (nếu đã chạy cả file từ trước thì chạy lại riêng đoạn này).
4. Trên mỗi máy: mở app → chuông 🔔 → **Bật thông báo đẩy** → cho phép. iPhone cần iOS 16.4+ và app đã thêm vào màn hình chính.

Sự kiện gửi thông báo: chủ giao việc / chuyển GẤP / đổi lịch / định giá phát sinh → KTV; KTV bắt đầu, rời, đổi trạng thái, hoàn thành, giao hàng, phát sinh, thu/chưa thu tiền, chi mua ngoài, bị gắn cờ → chủ. Bấm thông báo mở đúng việc.

## Bước 2 — Đưa lên mạng (Vercel hoặc Netlify, 5 phút)

Cách đơn giản nhất, không cần cài gì:

1. Vào https://app.netlify.com/drop (hoặc https://vercel.com/new → *Deploy a static site*).
2. Kéo thả cả thư mục `deploy` vào trang.
3. Nhận được địa chỉ dạng `https://ten-cua-hang.netlify.app`. Có thể đổi tên miền con trong *Site settings → Domain*.

## Cập nhật tự động đến mọi máy

- **Mã nguồn**: mỗi lần có bản mới, chạy `python3 build.py` trong thư mục `deploy` (đóng dấu phiên bản vào `sw.js`) rồi kéo thả lại thư mục lên Netlify/Vercel. Máy của chủ và KTV khi mở app (hoặc mỗi 15 phút khi đang mở) sẽ thấy thanh "⬆ Có bản cập nhật mới – nhấn để tải lại"; không phải cài lại gì.
- **Dữ liệu**: Supabase đẩy thay đổi theo thời gian thực — chủ giao việc thì KTV thấy ngay; KTV bấm Bắt đầu / lập phiếu thì chủ thấy ngay. Dự phòng: app tự làm mới mỗi 30 giây khi đang mở và mỗi khi quay lại app.

## Bước 3 — Cài lên điện thoại / máy tính

- **iPhone/iPad (Safari)**: mở địa chỉ → nút *Chia sẻ* → **Thêm vào MH chính**.
- **Android (Chrome)**: mở địa chỉ → menu ⋮ → **Thêm vào màn hình chính** / **Cài đặt ứng dụng**.
- **Máy tính (Chrome/Edge)**: biểu tượng *Cài đặt* ở cuối thanh địa chỉ.

Sau khi cài, ứng dụng mở toàn màn hình như app bình thường. Mỗi người đăng nhập bằng email + mật khẩu đã cấp; đăng nhập một lần, lần sau tự vào.

## Phân quyền đã cài sẵn

- **Chủ**: toàn quyền; thấy giá vốn, giá bán, thu chi, báo cáo; đánh dấu đã thanh toán lại cho nhân viên.
- **Nhân viên**: thấy danh sách việc, cập nhật trạng thái/nhật ký/ảnh, xuất vật tư kho (không thấy giá), ghi khoản tự mua ngoài và theo dõi chủ đã thanh toán lại chưa, thu tiền khách, lập phiếu nghiệm thu cho khách ký.
- Giới hạn này được thực thi ở cơ sở dữ liệu (RLS), không chỉ ở giao diện.

## Tạo việc nhanh

Gõ tên khách hoặc dán số điện thoại: app tự nhận ra khách cũ, điền SĐT/tên và gợi ý các địa chỉ đã lưu (chọn hoặc gõ địa chỉ mới). Chỉ hai mức: *Bình thường* (hẹn mặc định sau 1 giờ) và *Gấp* (sau 30 phút, luôn xếp đầu danh sách; trong cùng mức, việc quá hạn lên trước). Nếu nhập giá chốt, KTV sẽ được báo số cần thu đúng lúc lập phiếu hoàn thành và phải chọn Đã thu tiền mặt / chuyển khoản / Chưa thu (ghi lý do); việc chưa thu đủ hiện nhãn cho chủ và cộng vào Báo cáo. Zalo cá nhân không có API nên tin nhắn vẫn phải nhập tay; nếu sau này dùng Zalo OA có thể nối API.

## Hình thức, ước tính và chuyển việc

- Mỗi việc có hình thức *tại công trình / từ xa / giao hàng*; việc tại công trình vẫn có nút phụ "Làm phần việc này từ xa" cho phần xử lý online (ca đó không áp quy tắc GPS, giờ tính riêng; việc tại công trình mà chỉ toàn ca từ xa sẽ bị gắn cờ trên phiếu). Việc có ước tính giờ (2h, 4h, 1 ngày, 2 ngày…) và % tiến độ KTV tự kéo. Việc từ xa vẫn tính giờ nhưng không áp quy tắc GPS 300 m.
- Bấm Bắt đầu ở việc khác khi đang mở một việc: việc cũ tự "Tạm dừng – chuyển sang CV-x" (không gắn cờ); quay lại bấm Tiếp tục. Giờ cộng dồn qua nhiều ca, nhiều ngày.
- Trong bộ lọc "Của tôi", KTV dùng ▲▼ để tự sắp thứ tự việc trong ngày.
- Hiệu suất có "Đúng dự toán giờ" và bảng giờ thực tế so với ước tính từng việc.

## Phiếu xác nhận hoàn thành

- Phiếu không ghi tiền: chỉ liệt kê các việc đã hoàn thành, vật tư bàn giao, ảnh/chữ ký, giờ và tọa độ. Giá trị công việc do chủ quản lý; KTV không thấy giá chốt, chỉ ghi số tiền khách đưa trực tiếp cho mình (nếu có).
- Việc từ xa: không ký, xác nhận bằng ảnh màn hình kết quả (tải lên) + ảnh tin nhắn khách.
- KTV ghi "Công việc phát sinh tại hiện trường" ngay trên phiếu; chủ thấy ở Báo cáo ("Phát sinh chờ định giá"), cập nhật giá chốt rồi bấm "Đã cập nhật giá chốt".

## Giao hàng (việc đã làm sẵn ở cửa hàng)

Chọn hình thức *Giao hàng (đã làm sẵn)*. Tại chỗ KTV chỉ bấm **Giao & xác nhận** → chụp 1 ảnh bàn giao trực tiếp (khách ký thêm nếu tiện) → **Giao xong**. App tự ghi GPS, giờ, lập phiếu bàn giao và đóng việc; không cần Bắt đầu/Rời.

## Nghiệm thu khi khách vắng mặt

Trong màn lập phiếu chọn **Khách vắng mặt · nghiệm thu bằng ảnh**: chụp ít nhất 1 ảnh thiết bị đã lắp / hiện trường bằng camera mở ngay trong app (không nhận ảnh có sẵn trong máy; mỗi ảnh đóng dấu chìm giờ, tọa độ, mã việc, tên KTV — cần cho phép quyền Camera lần đầu), đính thêm ảnh tin nhắn Zalo khách xác nhận nếu có, ghi tên người xác nhận. Phiếu in các ảnh này thay cho chữ ký và ghi rõ "nghiệm thu bằng ảnh".

## Các ràng buộc chống trốn việc (tóm tắt)

| Ràng buộc | Thực thi ở |
|---|---|
| Việc tại công trình: phải đang có mặt (bấm Bắt đầu tại công trình trong lần đến này) mới lập được phiếu — việc dở nhiều ngày thì ngày nghiệm thu cũng phải bấm Bắt đầu; việc từ xa: phải có ca Bắt đầu | giao diện + trigger CSDL |
| Mỗi lúc một KTV chỉ ở một công trình: Bắt đầu việc khác tự tạm dừng việc đang mở | giao diện |
| KTV không tự đặt Hoàn thành/Hủy; Hoàn thành chỉ qua phiếu | giao diện + trigger CSDL |
| Nhật ký, check-in ghi đúng người đăng nhập; KTV không sửa/xóa được | trigger + RLS |
| Ảnh nghiệm thu tại công trình chỉ chụp trực tiếp, đóng dấu giờ/GPS/mã việc/KTV | giao diện |
| Mốc vị trí công trình tự hình thành: lần Bắt đầu đầu tiên (GPS ≤ 60 m), hoặc link Google Maps khách gửi, hoặc địa chỉ trùng với địa điểm đã biết của khách; bắt đầu cách mốc > 300 m bị gắn cờ. Mỗi việc có địa chỉ riêng (nhà/cơ quan), khách lưu nhiều địa điểm | giao diện |
| Thao tác trong app cách điểm bắt đầu > 300 m → ca tự đóng, gắn cờ | giao diện |
| Ca quá 10 giờ: tính tối đa 10 giờ, gắn cờ; chủ có nút Đóng ca | giao diện |
| Phiếu gắn cờ khi ca không có GPS hoặc nghiệm thu < 10 phút | giao diện |
| KTV không thấy giá chốt, giá vốn, giá bán vật tư | RLS (view items_staff) |
| Chỉ chủ tạo việc mới; KTV ghi phát sinh trong phiếu | giao diện + RLS |

Những dòng "giao diện" có thể bị KTV rành kỹ thuật lách bằng cách sửa dữ liệu qua API nếu có khóa anon; vì vậy các ràng buộc quan trọng nhất đã đưa vào trigger/RLS. Nếu cần siết hoàn toàn, tôi có thể chuyển thêm các kiểm tra khoảng cách vào trigger.

## Định vị GPS và chống bỏ công trình

- KTV bấm **Bắt đầu tại công trình** khi đến và **Hoàn thành & lập phiếu** / **Tạm rời công trình** khi đi; mỗi lần bấm ghi giờ + tọa độ (có link mở Google Maps). Phiếu nghiệm thu cũng ghi tọa độ lúc khách ký.
- Trình duyệt sẽ hỏi quyền vị trí lần đầu; ứng dụng phải chạy trên HTTPS (Netlify/Vercel có sẵn). Trên iPhone: Cài đặt → Quyền riêng tư → Dịch vụ định vị → Safari/ứng dụng → Khi dùng.
- Chủ xem mục **Báo cáo → Hiện diện hôm nay** và **Hiệu suất** (giờ tại công trình theo ngày, việc xong theo tuần, bảng xếp hạng). KTV chỉ thấy số liệu của chính mình.
- KTV quên bấm rời: băng-rôn "Đang tại công trình" luôn hiện trên đầu app với nút Rời; thao tác trong app khi cách điểm bắt đầu hơn 300 m thì ca tự đóng và gắn cờ "rời công trình không bấm"; bắt đầu việc khác thì ca cũ tự đóng; ca quá 10 giờ chỉ tính 10 giờ và gắn cờ; chủ có nút "Đóng ca" ở Báo cáo. Tab Hiệu suất hiện số ca có cờ / tổng ca.

## Lưu ý

- Ảnh hiện trường/hóa đơn được thu nhỏ và lưu thẳng trong cơ sở dữ liệu; đủ cho quy mô cửa hàng.
- Sao lưu: Supabase → *Database → Backups* (gói miễn phí giữ bản hằng ngày trong 7 ngày); có thể xuất CSV từng bảng bất cứ lúc nào ở *Table Editor*.
