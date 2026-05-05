import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://qhpfppsdjmibucurucui.supabase.co/rest/v1/');
  await http.get(url, headers: {
    'apikey': 'sb_publishable_EmsYOaccLHFQg2FEFFn5qw_xxqUd1bo',
  });
}
