package services.applicant.question;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableSet;
import java.util.Optional;
import services.MessageKey;
import services.Path;
import services.applicant.ValidationErrorMessage;
import services.question.types.IDQuestionDefinition;
import services.question.types.QuestionType;

/**
 * Represents an id question in the context of a specific applicant.
 *
 * <p>See {@link ApplicantQuestion} for details.
 */
public class IDQuestion implements PresentsErrors {

  private final ApplicantQuestion applicantQuestion;
  private Optional<String> idValue;

  public IDQuestion(ApplicantQuestion applicantQuestion) {
    this.applicantQuestion = applicantQuestion;
    assertQuestionType();
  }

  @Override
  public ImmutableList<Path> getAllPaths() {
    return ImmutableList.of(getIDPath());
  }

  @Override
  public boolean hasQuestionErrors() {
    return !getQuestionErrors().isEmpty();
  }

  @Override
  public ImmutableSet<ValidationErrorMessage> getQuestionErrors() {
    if (!isAnswered()) {
      return ImmutableSet.of();
    }

    IDQuestionDefinition definition = getQuestionDefinition();
    int idLength = getIDValue().map(s -> s.length()).orElse(0);
    ImmutableSet.Builder<ValidationErrorMessage> errors = ImmutableSet.builder();

    if (definition.getMinLength().isPresent()) {
      int minLength = definition.getMinLength().getAsInt();
      if (idLength < minLength) {
        errors.add(ValidationErrorMessage.create(MessageKey.ID_VALIDATION_TOO_SHORT, minLength));
      }
    }

    if (definition.getMaxLength().isPresent()) {
      int maxLength = definition.getMaxLength().getAsInt();
      if (idLength > maxLength) {
        errors.add(ValidationErrorMessage.create(MessageKey.ID_VALIDATION_TOO_LONG, maxLength));
      }
    }

    // Make sure the entered id is an int
    if (idLength != 0 && !getIDValue().get().matches("^[0-9]*$")) {
      errors.add(ValidationErrorMessage.create(MessageKey.ID_VALIDATION_NUMBER_REQUIRED));
    }

    return errors.build();
  }

  @Override
  public boolean hasTypeSpecificErrors() {
    return !getAllTypeSpecificErrors().isEmpty();
  }

  @Override
  public ImmutableSet<ValidationErrorMessage> getAllTypeSpecificErrors() {
    // Add id specific errors
    return ImmutableSet.of();
  }

  public ImmutableSet<ValidationErrorMessage> getNumberErrorMessage() {
    return ImmutableSet.of(ValidationErrorMessage.create(MessageKey.ID_VALIDATION_NUMBER_REQUIRED));
  }

  @Override
  public boolean isAnswered() {
    return applicantQuestion.getApplicantData().hasPath(getIDPath());
  }

  public Optional<String> getIDValue() {
    if (idValue != null) {
      return idValue;
    }
    idValue = applicantQuestion.getApplicantData().readString(getIDPath());
    return idValue;
  }

  public void assertQuestionType() {
    if (!applicantQuestion.getType().equals(QuestionType.ID)) {
      throw new RuntimeException(
          String.format(
              "Question is not an ID question: %s (type: %s)",
              applicantQuestion.getQuestionDefinition().getQuestionPathSegment(),
              applicantQuestion.getQuestionDefinition().getQuestionType()));
    }
  }

  public IDQuestionDefinition getQuestionDefinition() {
    assertQuestionType();
    return (IDQuestionDefinition) applicantQuestion.getQuestionDefinition();
  }

  public Path getIDPath() {
    return applicantQuestion.getContextualizedPath().join(Scalar.ID);
  }

  @Override
  public String getAnswerString() {
    return getIDValue().orElse("-");
  }
}
