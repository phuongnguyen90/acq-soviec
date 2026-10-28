// Điền 2 giá trị lấy từ Supabase → Project Settings → API.
// Để trống cả hai = chạy thử nghiệm, dữ liệu lưu trên máy (không dùng chung).
window.APP_CONFIG = {
  supabaseUrl: "",   // VD: "https://abcdefghijk.supabase.co"
  supabaseKey: "",   // khóa "anon public" (an toàn để đưa lên web vì đã có phân quyền RLS)
  vapidPublicKey: "BGIYwTuCTkrBLKCwRW4r6c4ox3MIMYvOvIqQGHtmsf3QFRgKusxsMOsrq6sld_DfTE_riJVAqEog7kscqMHeqXE" // khóa công khai cho thông báo đẩy (cặp với khóa bí mật trong supabase/VAPID.txt)
};
