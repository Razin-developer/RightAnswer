import 'package:flutter/material.dart';

import '../services/app_link_service.dart';
import 'chat_screen.dart';
import 'exam_screen.dart';
import 'home_screen.dart';
import 'study_plan_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialChatId;
  final String? initialSubjectId;
  final String? initialChapterId;
  final String? initialStudyPlanId;

  const MainScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialChatId,
    this.initialSubjectId,
    this.initialChapterId,
    this.initialStudyPlanId,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex.clamp(0, 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLinkService.instance.retryPendingLinkIfPossible();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ChatScreen(initialChatId: widget.initialChatId),
          const ExamScreen(),
          StudyPlanScreen(initialPlanId: widget.initialStudyPlanId),
          HomeScreen(
            initialSubjectId: widget.initialSubjectId,
            initialChapterId: widget.initialChapterId,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz_rounded),
            label: 'Exams',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'Study',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Subjects',
          ),
        ],
      ),
    );
  }
}
