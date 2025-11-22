import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'support_ticket_detail_page.dart';

class SupportTicketListPage extends StatefulWidget {
  const SupportTicketListPage({Key? key}) : super(key: key);

  @override
  State<SupportTicketListPage> createState() => _SupportTicketListPageState();
}

class _SupportTicketListPageState extends State<SupportTicketListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['Pending', 'In Progress', 'Resolved'];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _tabController = TabController(length: _tabs.length, vsync: this);
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Text("support_tickets".tr()),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: _tabs.map((key) => Tab(text: key.tr())).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((String status) {
          return TicketList(status: status, currentUserId: _currentUserId);
        }).toList(),
      ),
    );
  }
}

class TicketList extends StatefulWidget {
  final String status;
  final String? currentUserId;
  const TicketList({Key? key, required this.status, this.currentUserId}) : super(key: key);
  @override
  State<TicketList> createState() => _TicketListState();
}

class _TicketListState extends State<TicketList> {
  late Future<List<Map<String, dynamic>>> _ticketsFuture;

  @override
  void initState() {
    super.initState();
    _ticketsFuture = _fetchTickets();
  }

  Future<List<Map<String, dynamic>>> _fetchTickets() async {
    final response = await Supabase.instance.client
        .from('support_tickets')
        .select()
        .eq('status', widget.status)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _refresh() async {
    setState(() {
      _ticketsFuture = _fetchTickets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ticketsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        final tickets = snapshot.data!;
        if (tickets.isEmpty) {
          return Center(
            child: Text(
              "No ${widget.status.toLowerCase()} tickets found.",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              final ticket = tickets[index];
              final createdAt = DateTime.parse(ticket['created_at']);
              final assignedId = ticket['assigned_admin_id'];
              final assignedName = ticket['assigned_admin_name'];

              String assignmentText = '';
              Color assignmentColor = Colors.grey;
              IconData assignmentIcon = Icons.person_outline;

              if (assignedId == null) {
                assignmentText = 'Unassigned';
                assignmentColor = Colors.orange;
                assignmentIcon = Icons.assignment_late_outlined;
              } else if (assignedId == widget.currentUserId) {
                assignmentText = 'Assigned to Me';
                assignmentColor = Colors.green;
                assignmentIcon = Icons.assignment_ind;
              } else {
                assignmentText = 'Worked on by ${assignedName ?? 'Admin'}';
                assignmentColor = Colors.blue;
                assignmentIcon = Icons.lock_outline;
              }

              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.support_agent, color: Colors.teal),
                  title: Text(
                    ticket['user_name'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket['message'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(assignmentIcon, size: 12, color: assignmentColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              assignmentText,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: assignmentColor,
                                  fontWeight: FontWeight.w500
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  trailing: Text(
                    DateFormat('dd MMM, hh:mm a').format(createdAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EnhancedSupportTicketDetailPage(ticket: ticket),
                      ),
                    );
                    if (result == true) {
                      _refresh();
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}