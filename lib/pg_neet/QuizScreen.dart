import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mymedicosweb/pg_neet/ResultScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

class QuizPage extends StatefulWidget {
  final String quizId;
  final String title;
  final String duedate;
  final int discount;

  QuizPage(
      {Key? key,
      required this.quizId,
      required this.title,
      required this.duedate,
      required this.discount})
      : super(key: key);

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int currentQuestionIndex = 0;
  List<Map<String, dynamic>> questions = [];
  List<int?> selectedAnswers = [];
  List<bool> questionsMarkedForReview = [];
  late Timer _timer;
  int _remainingTime = 12600; // Time in seconds (210 minutes)
  bool _timeUp = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    html.document.documentElement?.requestFullscreen();
    fetchPhoneNumberFromLocalStorage();
    _fetchQuizData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  void exitFullscreenAfterDelay() {

      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }

  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _timeUp = true;
          _timer.cancel();
        }
      });
    });
  }

  Future<void> fetchPhoneNumberFromLocalStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? phoneNumber = prefs.getString('phoneNumber');
    if (phoneNumber != null) {
      deductCoinsAndNavigate(phoneNumber,widget.discount);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> deductCoinsAndNavigate(String phoneNumber, int discount) async {
    setState(() {
      _isLoading = true;
    });
    DatabaseReference databaseReference = FirebaseDatabase.instance.reference();
    DataSnapshot snapshot = await databaseReference
        .child('profiles')
        .child(phoneNumber)
        .child('coins')
        .get();
    int currentCoins = snapshot.value as int;

    if (currentCoins >= 50-discount) {
      // Deduct 50 coins
      currentCoins -= 50-discount;
      await databaseReference
          .child('profiles')
          .child(phoneNumber)
          .child('coins')
          .set(currentCoins);

      // Navigate to QuizPage
    } else {
      // Show error message if not enough coins
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough coins to proceed.'),
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchQuizData() async {
    try {
      CollectionReference quizCollection = FirebaseFirestore.instance
          .collection("PGupload")
          .doc("Weekley")
          .collection("Quiz");

      QuerySnapshot querySnapshot = await quizCollection.get();
      for (QueryDocumentSnapshot document in querySnapshot.docs) {
        Map<String, dynamic> data = document.data() as Map<String, dynamic>;

        String? qid = document.get('qid'); // Fetch the quiz ID
        print("qid: $qid");

        // Check if qid is not null and matches the widget's quizId
        if (qid != null && qid == widget.quizId) {
          List<dynamic> dataList = data['Data'];
          for (var entry in dataList) {
            Neetpg question = Neetpg(
              question: entry['Question'] ?? '',
              optionA: entry['A'] ?? '',
              optionB: entry['B'] ?? '',
              optionC: entry['C'] ?? '',
              optionD: entry['D'] ?? '',
              correctAnswer: entry['Correct'] ?? '',
              imageUrl: entry['Image'] ?? '',
              description: entry['Description'] ?? '',
            );
            questions.add(question.toMap()); // Convert Neetpg object to a map
            selectedAnswers.add(null);
            questionsMarkedForReview.add(false);
          }

          // Assuming you want to stop after fetching one quiz
        }
      }

      setState(() {}); // Update the UI after fetching data
    } catch (e) {
      print("Error fetching quiz data: $e");
    }
  }

  void selectAnswer(int? answer) {
    setState(() {
      if (selectedAnswers[currentQuestionIndex] == answer) {
        // If the same option is selected again, deselect it
        selectedAnswers[currentQuestionIndex] = null;
      } else {
        // Otherwise, select the new option
        selectedAnswers[currentQuestionIndex] = answer;
      }
    });
  }

  void toggleMarkForReview() {
    setState(() {
      questionsMarkedForReview[currentQuestionIndex] =
          !questionsMarkedForReview[currentQuestionIndex];
    });
  }

  void goToNextQuestion() {
    setState(() {
      currentQuestionIndex = (currentQuestionIndex + 1) % questions.length;
    });
  }

  void goToPreviousQuestion() {
    setState(() {
      currentQuestionIndex = (currentQuestionIndex - 1) % questions.length;
      if (currentQuestionIndex < 0) {
        currentQuestionIndex = questions.length - 1;
      }
    });
  }

  Future<void> _submitQuiz() async {
    html.document.exitFullscreen();
    int correctAnswers = 0;
    int skip = 0;

    for (int i = 0; i < questions.length; i++) {
      if (selectedAnswers[i] == null) {
        skip++;
      } else if (questions[i]['Correct'] == selectedAnswers[i].toString()) {
        correctAnswers++;
      }
    }

    int totalQuestions = questions.length;
    int score =
        (correctAnswers * 100) ~/ totalQuestions; // Example scoring formula

    // Upload the quiz result
    QuizResultUploader uploader = QuizResultUploader();
    await uploader.uploadQuizResult(
      id: widget.quizId,
      correctAnswers: correctAnswers,
      totalQuestions: totalQuestions,
      remainingTime: _remainingTime,
      score: score,
      skip: skip,
    );
    exitFullscreenAfterDelay();
    context.go(
      '/examdetails/examscreen/resultscreen',
      extra: {
        'quizId': widget.quizId,
        'quizTitle': widget.title,
        'questions': questions,
        'selectedAnswers': selectedAnswers,
        'remainingTime': _remainingTime,
        'dueDate': widget.duedate,
      },
    );


    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => QuizResultScreen(
    //       quizId: widget.quizId,
    //       quizTitle: widget.title,
    //       questions: questions,
    //       selectedAnswers: selectedAnswers,
    //       remainingTime: _remainingTime,
    //       dueDate: widget.duedate,
    //     ),
    //   ),
    // ).then((_) {
    //   // Exit fullscreen after navigating
    //   exitFullscreenAfterDelay();
    // });
  }

  void clearSelection() {
    setState(() {
      selectedAnswers[currentQuestionIndex] = null;
    });
  }

  @override
  Widget build(BuildContext context) {








    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !kIsWeb,
          backgroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title), // Grandtest heading
              Text(
                DateFormat('dd MMMM yyyy').format(DateTime.parse(widget.duedate)),
                style: const TextStyle(fontSize: 12),
              ),

            ],
          ),
          actions: [
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(
                    8), // Adjust the border radius as needed
              ),
              child: ElevatedButton(
                onPressed: _submitQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors
                      .transparent, // Make the button transparent to show the container's background color
                  elevation: 0, // Remove elevation
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                        8), // Adjust the border radius to match the container
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: 10, horizontal: 16), // Adjust padding as needed
                  child: Text(
                    'End Quiz',
                    style: TextStyle(
                      color: Colors.white, // Text color
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 600;

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight + 1),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black,
                    width: 2.0,
                  ),
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.white,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 24,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    Text(
                      DateFormat('dd MMMM yyyy').format(DateTime.parse(widget.duedate)),
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ElevatedButton(
                      onPressed: _submitQuiz,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        child: Text(
                          'End Quiz',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          drawer: isMobile
              ? Drawer(
            backgroundColor: Colors.white,
                  child: Column(
                    children: [
                      InstructionPanel(
                        notVisited:
                            selectedAnswers.where((a) => a == null).length,
                        notAnswered:
                            selectedAnswers.where((a) => a == null).length,
                        answered:
                            selectedAnswers.where((a) => a != null).length,
                        markedForReview:
                            questionsMarkedForReview.where((r) => r).length,
                        // answeredAndMarkedForReview: selectedAnswers
                        //     .asMap()
                        //     .entries
                        //     .where((entry) =>
                        // entry.value != null &&
                        //     questionsMarkedForReview[entry.key])
                        //     .length,
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.black,
                                width: 2.0), // Border styling
                            borderRadius: BorderRadius.circular(
                                0.0), // Optional: rounded corners
                          ),
                          child: QuestionNavigationPanel(
                            questionCount: questions.length,
                            currentQuestionIndex: currentQuestionIndex,
                            questionsMarkedForReview: questionsMarkedForReview,
                            selectedAnswers: selectedAnswers,
                            onSelectQuestion: (index) {
                              setState(() {
                                currentQuestionIndex = index;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          body: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // HeaderSection(remainingTime: _remainingTime),
                    Container(
                      color: Colors
                          .white, // Set the background color of the question section to white
                      child: QuestionSection(
                        question: questions[currentQuestionIndex]['Question'],
                        image: questions[currentQuestionIndex]['Image'],
                        options: [
                          questions[currentQuestionIndex]['A'],
                          questions[currentQuestionIndex]['B'],
                          questions[currentQuestionIndex]['C'],
                          questions[currentQuestionIndex]['D'],
                        ],
                        selectedAnswer: selectedAnswers[currentQuestionIndex],
                        onAnswerSelected: selectAnswer,
                        remainingTime: _remainingTime,
                      ),
                    ),
                    NavigationButtons(
                      onNextPressed: goToNextQuestion,
                      onPreviousPressed: goToPreviousQuestion,
                      onMarkForReviewPressed: toggleMarkForReview,
                      isMarkedForReview: questionsMarkedForReview[
                          currentQuestionIndex], // Assuming questionsMarkedForReview is a list of booleans
                    ),
                  ],
                ),
              ),
              if (!isMobile)
                Container(
                  width: 400,
                  // Adjust the width as needed
                  color: Colors.white,
                  // Background color for the side panel
                  child: Column(
                    children: [
                      InstructionPanel(
                        notVisited:
                            selectedAnswers.where((a) => a == null).length,
                        notAnswered:
                            selectedAnswers.where((a) => a == null).length,
                        answered:
                            selectedAnswers.where((a) => a != null).length,
                        markedForReview:
                            questionsMarkedForReview.where((r) => r).length,
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.black,
                                width: 2.0), // Border styling
                            borderRadius: BorderRadius.circular(
                                0.0), // Optional: rounded corners
                          ),
                          child: QuestionNavigationPanel(
                            questionCount: questions.length,
                            currentQuestionIndex: currentQuestionIndex,
                            questionsMarkedForReview: questionsMarkedForReview,
                            selectedAnswers: selectedAnswers,
                            onSelectQuestion: (index) {
                              setState(() {
                                currentQuestionIndex = index;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class Neetpg {
  final String question;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctAnswer;
  final String imageUrl;
  final String description;

  Neetpg({
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctAnswer,
    required this.imageUrl,
    required this.description,
  });

  factory Neetpg.fromJson(Map<String, dynamic> json) {
    return Neetpg(
      question: json['Question'] ?? '',
      optionA: json['A'] ?? '',
      optionB: json['B'] ?? '',
      optionC: json['C'] ?? '',
      optionD: json['D'] ?? '',
      correctAnswer: json['Correct'] ?? '',
      imageUrl: json['Image'] ?? '',
      description: json['Description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'Question': question,
      'A': optionA,
      'B': optionB,
      'C': optionC,
      'D': optionD,
      'Correct': correctAnswer,
      'Image': imageUrl,
      'Description': description,
    };
  }
}

class HeaderSection extends StatelessWidget {
  final int remainingTime;

  HeaderSection({required this.remainingTime});

  @override
  Widget build(BuildContext context) {
    int hours = remainingTime ~/ 3600;
    int minutes = (remainingTime % 3600) ~/ 60;
    int seconds = remainingTime % 60;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Candidate Name: [Your Name]',
              style: TextStyle(fontSize: 16, fontFamily: 'Inter')),
          const Text('Exam Name: NEET PG',
              style: TextStyle(fontSize: 16, fontFamily: 'Inter')),
          const Text('Subject Name: English-Paper 2-Dec-2019',
              style: TextStyle(fontSize: 16, fontFamily: 'Inter')),
          Text(
            'Remaining Time: $hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}





class ImageDisplayWidget extends StatefulWidget {
  final String image;

  const ImageDisplayWidget({Key? key, required this.image}) : super(key: key);

  @override
  _ImageDisplayWidgetState createState() => _ImageDisplayWidgetState();
}

class _ImageDisplayWidgetState extends State<ImageDisplayWidget> {
  void _openFullScreenImage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImage(image: widget.image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFullScreenImage,
      child: SizedBox(
        width: double.infinity,
        height: 200,
        child: CachedNetworkImage(
          imageUrl: widget.image,
          fit: BoxFit.cover,
          placeholder: (context, url) => CircularProgressIndicator(),
          errorWidget: (context, url, error) => Icon(Icons.error),
        ),
      ),
    );
  }
}

class FullScreenImage extends StatelessWidget {
  final String image;

  const FullScreenImage({Key? key, required this.image}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],  // Changed to grey
      body: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
        },
        child: Center(
          child: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 3.0,
            child: CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.contain,
              placeholder: (context, url) => CircularProgressIndicator(),
              errorWidget: (context, url, error) => Icon(Icons.error),
            ),
          ),
        ),
      ),
    );
  }
}

class QuestionSection extends StatelessWidget {
  final String question;
  final List<String> options;
  final int? selectedAnswer;
  final String image;
  final ValueChanged<int?> onAnswerSelected;
  final int remainingTime;

  QuestionSection({
    required this.question,
    required this.options,
    required this.selectedAnswer,
    required this.onAnswerSelected,
    required this.image,
    required this.remainingTime,
  });

  @override
  Widget build(BuildContext context) {
    int hours = remainingTime ~/ 3600;
    int minutes = (remainingTime % 3600) ~/ 60;
    int seconds = remainingTime % 60;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Question:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(0),
                ),
                padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Text(
                  'Remaining Time: $hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Inter',
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  // Handle tap on '+4 correct'
                  print('Tapped on +4 correct');
                  // Add your logic here for what happens when users tap on '+4 correct'
                },
                child: Text(
                  '+4 correct',
                  style: TextStyle(
                    fontSize: 20, // Adjust the font size as needed
                    color: Colors.green,
                    fontFamily: 'Inter', // Font family
                    decoration: TextDecoration.underline, // Underline the text on tap
                  ),
                ),
              ),
              SizedBox(width: 16), // Adjust spacing between texts
              GestureDetector(
                onTap: () {
                  // Handle tap on '-1 wrong'
                  print('Tapped on -1 wrong');
                  // Add your logic here for what happens when users tap on '-1 wrong'
                },
                child: Text(
                  '-1 wrong',
                  style: TextStyle(
                    fontSize: 20, // Adjust the font size as needed
                    color: Colors.red,
                    fontFamily: 'Inter', // Font family
                    decoration: TextDecoration.underline, // Underline the text on tap
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              question,
              style: const TextStyle(fontSize: 16, fontFamily: 'Inter'),
            ),
          ),
          const SizedBox(height: 10),
          if (image.isNotEmpty && image != "noimage")
            ImageDisplayWidget(image: image),
          const SizedBox(height: 20),
          ...options.asMap().entries.map((entry) {
            int idx = entry.key;
            String option = entry.value;
            String letter = String.fromCharCode(65 + idx); // Convert index to letter (A, B, C, ...)
            return InkWell(
              onTap: () {
                onAnswerSelected(idx);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: selectedAnswer == idx ? const Color(0xFF5BFC8B) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24, // Adjust the width as needed
                      height: 24, // Adjust the height as needed
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5BFC8B),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        letter,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          color: selectedAnswer == idx ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}


class NavigationButtons extends StatelessWidget {
  final VoidCallback? onNextPressed;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onMarkForReviewPressed;
  final bool isMarkedForReview;

  const NavigationButtons({
    this.onNextPressed,
    this.onPreviousPressed,
    this.onMarkForReviewPressed,
    required this.isMarkedForReview,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 600;

        return isMobile
            ? Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _checkbox(
                          onPressed: onMarkForReviewPressed,
                          label: 'Mark for Review',
                          isChecked: isMarkedForReview,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                      height:
                          16), // Adjust spacing between the two rows of buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _customButton(
                          onPressed: onPreviousPressed,
                          label: 'Previous',
                        ),
                      ),
                      Expanded(
                        child: _customButton(
                          onPressed: onNextPressed,
                          label: 'Next',
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(width: 15),
                  _checkbox(
                    onPressed: onMarkForReviewPressed,
                    label: 'Mark for Review',
                    isChecked: isMarkedForReview,
                  ),
                  const SizedBox(
                      width:
                          500), // Adjust spacing between the two sets of buttons
                  _customButton(
                    onPressed: onPreviousPressed,
                    label: 'Previous',
                    buttonColor: Colors.grey,
                  ),
                  const SizedBox(width: 40,),
                  _customButton(
                    onPressed: onNextPressed,
                    label: 'Next',
                    buttonColor: Colors.black,
                  ),
                  const SizedBox(width: 10),
                ],
              );
      },
    );
  }

  Widget _customButton({
    required VoidCallback? onPressed,
    required String label,
    Color? buttonColor, // Optional color parameter
  }) {
    return SizedBox(
      width: 150, // Set the desired width
      height: 50, // Set the desired height
      child: Container(
        decoration: BoxDecoration(
          color: buttonColor ??
              Colors
                  .black, // Use buttonColor if provided, otherwise fallback to Colors.black
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkbox({
    required VoidCallback? onPressed,
    required String label,
    required bool isChecked,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Checkbox(
            value: isChecked,
            onChanged: (_) => onPressed?.call(),
            activeColor: Colors.green,
            visualDensity: VisualDensity.adaptivePlatformDensity, // Adjusts the size of the checkbox
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontFamily: 'Inter'
            ),
          ),
        ],
      ),
    );
  }
}

class InstructionPanel extends StatelessWidget {
  final int notVisited;
  final int notAnswered;
  final int answered;
  final int markedForReview;

  const InstructionPanel({
    super.key,
    required this.notVisited,
    required this.notAnswered,
    required this.answered,
    required this.markedForReview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8.0), // Add left padding
      decoration: const BoxDecoration(
        border: Border.symmetric(
          vertical: BorderSide(
            color: Colors.black,
            width: 2.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Questionnaire Summary :",
            style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 20),
          ),
          InstructionTile(
            color: Colors.grey,
            label: 'Not Visited',
            count: notVisited,
          ),
          InstructionTile(
            color: Colors.red,
            label: 'Not Answered',
            count: notAnswered,
          ),
          InstructionTile(
            color: Colors.green,
            label: 'Answered',
            count: answered,
          ),
          InstructionTile(
            color: Colors.purple,
            label: 'Marked for Review',
            count: markedForReview,
          ),
        ],
      ),
    );
  }
}

class InstructionTile extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  InstructionTile({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Perform any action on tile tap
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white, // Inside color
                border: Border.all(color: color, width: 2),
                borderRadius:
                    BorderRadius.circular(10), // Slightly rounded corners
              ),
              child: Center(
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color, // Text color same as border color
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color, // Label color same as border color
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class QuestionNavigationPanel extends StatelessWidget {
  // New property for heading
  final int questionCount;
  final int currentQuestionIndex;
  final List<bool> questionsMarkedForReview;
  final List<int?> selectedAnswers;
  final ValueChanged<int> onSelectQuestion;

  QuestionNavigationPanel({
    // Initialize the heading
    required this.questionCount,
    required this.currentQuestionIndex,
    required this.questionsMarkedForReview,
    required this.selectedAnswers,
    required this.onSelectQuestion,
  });

  @override
  Widget build(BuildContext context) {
    String heading = "Navigate and Review :";
    return
      SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child:Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        // Wrap the GridView.builder inside a Column
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text(
              heading, // Display the heading
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              " Assure yourself navigate from anywhere", // Display the heading
              style: TextStyle(
                  fontSize: 14, color: Colors.grey, fontFamily: 'Inter'),
            ),
          ),


             Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 4.0,
                    mainAxisSpacing: 4.0,
                  ),
                  itemCount: questionCount,
                  itemBuilder: (context, index) {
                    bool markedForReview = questionsMarkedForReview[index];
                    bool hasSelectedAnswer = selectedAnswers[index] != null;

                    Color borderColor = Colors.grey;
                    if (markedForReview) {
                      borderColor = Colors.purple;
                    } else if (hasSelectedAnswer) {
                      borderColor = Colors.green;
                    } else if (currentQuestionIndex == index) {
                      borderColor = Colors.blue;
                    }

                    return GestureDetector(
                      onTap: () => onSelectQuestion(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: borderColor, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            (index + 1).toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: borderColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],

          ),
        ],
      ),
      ),
    );
  }
}

class QuizResultUploader {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> uploadQuizResult({
    required String id,
    required int correctAnswers,
    required int totalQuestions,
    required int remainingTime,
    required int score,
    required int skip,
  }) async {
    try {
      // Get the current user
      String? userId = FirebaseAuth.instance.currentUser?.phoneNumber;
      if (userId != null) {
        // Reference to the user's quiz results collection
        CollectionReference<Map<String, dynamic>> userResultsRef =
            _firestore.collection('QuizResults').doc(userId).collection('Exam');

        // Create a map with the quiz result data
        Map<String, dynamic> resultData = {
          'ID': id,
          'correctAnswers': correctAnswers,
          'totalQuestions': totalQuestions,
          'remainingTime': remainingTime,
          'Score': score,
          'skip': skip,
          'timestamp': Timestamp.now(),
        };

        // Upload the quiz result data to Firestore with the specified ID
        await userResultsRef.doc(id).set(resultData);

        print('Quiz result uploaded successfully.');
      } else {
        print('User not logged in.');
      }
    } catch (error) {
      print('Error uploading quiz result: $error');
    }
  }
}
