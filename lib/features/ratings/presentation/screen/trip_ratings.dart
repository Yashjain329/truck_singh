import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:easy_localization/easy_localization.dart';
import '../../../../config/theme.dart';

class TripRatingsPage extends StatefulWidget {
  const TripRatingsPage({super.key});

  @override
  State<TripRatingsPage> createState() => _TripRatingsPageState();
}

class _TripRatingsPageState extends State<TripRatingsPage> {
  final ptr.RefreshController _refreshController = ptr.RefreshController();
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRatings();
  }

  String trimAddress(String address) {
    String cleaned = address
        .replaceAll(
          RegExp(
            r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      return "${parts[0]},${parts[parts.length - 2]}";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  Future<void> _fetchRatings() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception(tr("error_user_not_authenticated"));
      }

      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (profile == null) {
        throw Exception(tr("error_user_profile_not_found"));
      }

      final customUserId = profile['custom_user_id'] as String?;

      final response = await supabase
          .from('view_user_ratings')
          .select(
            '*, shipment:shipment(shipment_id, pickup, drop, assigned_agent, assigned_driver, shipper_id)',
          )
          .eq('ratee_id', customUserId!);

      List<Map<String, dynamic>> tempRatings = [];

      for (final r in response) {
        final shipment = r['shipment'];
        final raterId = r['rater_id'] as String?;

        String? raterName;
        String? raterRole;

        if (raterId != null) {
          if (shipment['assigned_agent'] == raterId) {
            raterRole = "Agent";
          } else if (shipment['assigned_driver'] == raterId) {
            raterRole = "Driver";
          } else if (shipment['shipper_id'] == raterId) {
            raterRole = "Shipper";
          }

          final user = await supabase
              .from('user_profiles')
              .select('name')
              .eq('custom_user_id', raterId)
              .maybeSingle();

          raterName = user?['name'];
        }

        tempRatings.add({
          ...r,
          'pickup': trimAddress(shipment['pickup'] ?? ""),
          'drop': trimAddress(shipment['drop'] ?? ""),
          'rater_name': raterName ?? tr("na"),
          'rater_role': raterRole ?? tr("na"),
        });
      }

      if (mounted) {
        setState(() {
          _ratings = tempRatings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showTripDetailsPopup(BuildContext context, Map<String, dynamic> trip) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    tr("trip_details"),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _popupInfoCard(
                  Icons.numbers,
                  tr("trip_id"),
                  trip['shipment_id'].toString(),
                ),
                const SizedBox(height: 8),
                _popupInfoCard(
                  Icons.person,
                  tr("shipper"),
                  trip['rater_name'] ?? tr("na"),
                ),
                const SizedBox(height: 8),
                _popupInfoCard(
                  Icons.location_on,
                  tr("pickup"),
                  trip['pickup'] ?? "",
                ),
                const SizedBox(height: 8),
                _popupInfoCard(Icons.flag, tr("drop"), trip['drop'] ?? ""),

                const SizedBox(height: 16),
                Text(
                  tr("feedback"),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trip['feedback'] ?? tr("no_feedback"),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),

                const SizedBox(height: 16),

                Center(
                  child: RatingBarIndicator(
                    rating: (trip['rating'] ?? 0).toDouble(),
                    itemBuilder: (_, __) =>
                        const Icon(Icons.star, color: Colors.amber),
                    itemCount: 5,
                    itemSize: 22,
                  ),
                ),
                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr("close")),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _popupInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.orange.withValues(alpha: 0.2),
            child: Icon(icon, color: AppColors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 14),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (_ratings.isEmpty) return const SizedBox.shrink();

    final double avg =
        _ratings.map((r) => r['rating'] as int).reduce((a, b) => a + b) /
        _ratings.length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr("overall_performance"),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Text(tr("average_rating")),
                const SizedBox(width: 6),
                Text(
                  avg.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),

                RatingBarIndicator(
                  rating: avg,
                  itemBuilder: (_, __) =>
                      const Icon(Icons.star, color: Colors.amber),
                  itemCount: 5,
                  itemSize: 20,
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              "${tr("total_trips_rated")}: ${_ratings.length}",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("my_performance"))),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : _ratings.isEmpty
            ? ptr.SmartRefresher(
                controller: _refreshController,
                onRefresh: _fetchRatings,
                header: const ptr.WaterDropHeader(),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star_border_purple500_sharp,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          tr("no_ratings_yet"),
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr("no_ratings_yet_description"),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : ptr.SmartRefresher(
                controller: _refreshController,
                onRefresh: _fetchRatings,
                header: const ptr.WaterDropHeader(),
                child: ListView.builder(
                  itemCount: _ratings.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildSummaryCard();

                    final trip = _ratings[index - 1];

                    return InkWell(
                      onTap: () => _showTripDetailsPopup(context, trip),
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip['shipment_id'] ?? "Unknown",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),

                              if (trip['delivery_date'] != null &&
                                  trip['delivery_date'] != "")
                                Text(
                                  "completed : ${trip['delivery_date']}".tr(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),

                              const SizedBox(height: 6),

                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      'PICKUP: ${trimAddress(trip['pickup'] ?? "")}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              Row(
                                children: [
                                  const Icon(
                                    Icons.flag,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      'DROP: ${trimAddress(trip['drop'] ?? "")}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              RatingBarIndicator(
                                rating: (trip['rating'] ?? 0).toDouble(),
                                itemBuilder: (_, __) =>
                                    const Icon(Icons.star, color: Colors.amber),
                                itemCount: 5,
                                itemSize: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
